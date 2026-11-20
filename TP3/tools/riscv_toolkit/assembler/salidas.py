"""Salidas del ensamblador: la `Imagen` en el formato que consume cada herramienta (US-107).

- `.hex`: una palabra por línea, para `$readmemh` en los testbenches.
- `.bin`: las palabras en little-endian, igual que viajan en el payload de `LOAD` (protocolo §4).
- `.lst`: listado para leer: dirección, palabra, línea y fuente, con la expansión de cada
  pseudoinstrucción.
"""

import re

from riscv_toolkit.assembler.imagen import Imagen

_BYTES_PALABRA = 4

# Etiqueta al principio de una línea de la fuente (`loop: addi ...`), como la reconoce el lexer.
# En el listado las etiquetas van en su propio renglón, así que se sacan de la fuente.
_ETIQUETA = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_]*:")

# Columnas del listado: dirección, palabra, línea y fuente; la expansión de una pseudo va como
# comentario a partir de `_COLUMNA_NOTA`.
_ENCABEZADO = f"{'# dir':<5}  {'palabra':<8}  {'línea':>5}  fuente"
_COLUMNA_FUENTE = len(_ENCABEZADO) - len("fuente")
_COLUMNA_NOTA = _COLUMNA_FUENTE + 24


def a_hex(imagen: Imagen) -> str:
    """Una palabra por línea, 8 dígitos hex en minúscula (`00a28293`), como el .hex de GNU."""
    return "".join(f"{palabra:08x}\n" for palabra in imagen.palabras)


def a_bin(imagen: Imagen) -> bytes:
    """`4·N` bytes: cada palabra en little-endian, la de la dirección 0 primero."""
    return b"".join(palabra.to_bytes(_BYTES_PALABRA, "little") for palabra in imagen.palabras)


def a_lst(imagen: Imagen, texto: str) -> str:
    """Listado de `imagen`. `texto` es la fuente que se ensambló: `Imagen` solo guarda el número
    de línea de cada instrucción (`mapa_lineas`), no el texto.

        # dir  palabra   línea  fuente
                                inicio:
        0x000  00000013      4  nop                     # addi x0, x0, 0
        0x004  0000000b      -  halt                    # agregado por el ensamblador
    """
    fuente = texto.splitlines()
    etiquetas: dict[int, list[str]] = {}  # dirección → etiquetas que la nombran
    for nombre, direccion in imagen.simbolos.items():
        etiquetas.setdefault(direccion, []).append(nombre)

    renglones = [_ENCABEZADO]
    for i, palabra in enumerate(imagen.palabras):
        direccion = _BYTES_PALABRA * i
        renglones += _etiquetas(etiquetas.pop(direccion, []))
        nro = imagen.mapa_lineas.get(direccion)  # None: el halt que agregó el ensamblador
        nota: str | None  # comentario al final del renglón; None si no lleva
        if nro is None:
            linea, nota, columna_nro = "halt", "agregado por el ensamblador", "-"
        else:
            linea = _sin_etiqueta_ni_comentario(fuente[nro - 1])
            nota, columna_nro = imagen.expansiones.get(direccion), str(nro)
        renglon = f"0x{direccion:03x}  {palabra:08x}  {columna_nro:>5}  {linea}"
        if nota is not None:
            renglon = f"{renglon:<{_COLUMNA_NOTA}}# {nota}"
        renglones.append(renglon)

    # Etiquetas después de la última instrucción (`fin:` al final de un programa con halt).
    for direccion in sorted(etiquetas):
        renglones += _etiquetas(etiquetas[direccion])
    return "\n".join(renglones) + "\n"


def _etiquetas(nombres: list[str]) -> list[str]:
    """Un renglón por etiqueta, alineado con la columna de la fuente."""
    return [f"{' ' * _COLUMNA_FUENTE}{nombre}:" for nombre in nombres]


def _sin_etiqueta_ni_comentario(linea: str) -> str:
    """`loop:  addi x1, x1, 1  # suma` → `addi x1, x1, 1`."""
    sin_comentario = linea.split("#", 1)[0]
    return _ETIQUETA.sub("", sin_comentario).strip()
