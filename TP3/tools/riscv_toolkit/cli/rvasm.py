"""CLI `rvasm`: ensambla un .asm y escribe el .hex, .bin o .lst (US-107).

Es el subcomando `asm` de `python -m riscv_toolkit` (se corre desde `TP3/tools/`):

    uv run python -m riscv_toolkit asm programa.asm                    # → programa.hex
    uv run python -m riscv_toolkit asm programa.asm -o programa.bin    # formato por la extensión
    uv run python -m riscv_toolkit asm programa.asm --format lst -o -  # listado por pantalla

Errores y advertencias van a stderr con la forma `archivo:línea: ...`, que los editores
reconocen. Sale con 0 si generó la salida y con 1 si hubo un error de ensamblado o de archivo
(AC5); los errores de uso (opción inexistente, formato desconocido) salen con 2, como en argparse.
"""

import argparse
import sys
from collections.abc import Callable
from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.assembler.salidas import a_bin, a_hex, a_lst

# Formato a contenido del archivo. La fuente solo la necesita el .lst.
_FORMATOS: dict[str, Callable[[Imagen, str], bytes]] = {
    "hex": lambda imagen, _texto: a_hex(imagen).encode(),
    "bin": lambda imagen, _texto: a_bin(imagen),
    "lst": lambda imagen, texto: a_lst(imagen, texto).encode(),
}
_FORMATO_POR_DEFECTO = "hex"
_PANTALLA = "-"  # `-o -`: la salida va a stdout

_EXITO = 0
_ERROR = 1


def agregar_subcomando(
    subcomandos: "argparse._SubParsersAction[argparse.ArgumentParser]",
) -> None:
    """Registra `asm` en el parser de `__main__.py`."""
    parser = subcomandos.add_parser(
        "asm",
        help="ensambla un .asm y genera el .hex, .bin o .lst (rvasm)",
        description="Ensambla un programa y escribe la imagen en el formato pedido.",
    )
    # Nombre del archivo .asm
    parser.add_argument("entrada", type=Path, help="programa en assembly (.asm)")
    # Nombre del archivo de salida
    parser.add_argument(
        "-o",
        "--output",
        dest="salida",
        help="archivo de salida, o '-' para la pantalla (por defecto, la entrada con la "
        "extensión del formato)",
    )
    # Formato de la salida (hex, bin, lst)
    parser.add_argument(
        "--format",
        dest="formato",
        choices=list(_FORMATOS),
        help="formato de salida (por defecto, el de la extensión de -o, o hex)",
    )
    parser.set_defaults(ejecutar=ejecutar)


def ejecutar(args: argparse.Namespace) -> int:
    """Ensambla `args.entrada` y escribe la salida. Devuelve el código de salida."""
    entrada: Path = args.entrada
    formato = _elegir_formato(args.formato, args.salida)
    try:
        texto = entrada.read_text(encoding="utf-8")
        imagen = ensamblar(texto)
    except OSError as error:
        print(f"{entrada}: error: no se pudo leer: {error.strerror}", file=sys.stderr)
        return _ERROR
    except ErrorEnsamblado as error:
        print(f"{entrada}:{error.linea}: error: {error.mensaje}", file=sys.stderr)
        return _ERROR
    for advertencia in imagen.advertencias:
        print(f"{entrada}: advertencia: {advertencia}", file=sys.stderr)

    contenido = _FORMATOS[formato](imagen, texto)
    if args.salida == _PANTALLA:
        sys.stdout.flush()  # lo que ya se imprimió como texto tiene que salir antes
        sys.stdout.buffer.write(contenido)
        sys.stdout.buffer.flush()
        return _EXITO

    salida = Path(args.salida) if args.salida else entrada.with_suffix(f".{formato}")
    try:
        salida.write_bytes(contenido)
    except OSError as error:
        print(f"{salida}: error: no se pudo escribir: {error.strerror}", file=sys.stderr)
        return _ERROR
    print(f"{entrada} -> {salida} ({len(imagen.palabras)} palabras, {formato})")
    return _EXITO


def _elegir_formato(formato: str | None, salida: str | None) -> str:
    """`--format` si se da; si no, la extensión de `-o` si es un formato conocido; si no, hex."""
    if formato is not None:
        return formato
    if salida is not None:
        extension = Path(salida).suffix.removeprefix(".")
        if extension in _FORMATOS:
            return extension
    return _FORMATO_POR_DEFECTO
