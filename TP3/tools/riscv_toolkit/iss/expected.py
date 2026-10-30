"""Formato `.expected`: el estado final del golden model para los testbenches (US-108, AC6).

Lo escribe `rvsim --expect` y lo leen `tb_core_programs.v` (US-210) y `verify_rtl.py` (US-305).
Es una palabra hex de 8 dígitos por línea, así un testbench lo carga entero con `$readmemh`
(los comentarios `//` se ignoran y van sin acentos, por las herramientas de Verilog):

    [0]       motivo: 1 = HALTED, 2 = ILLEGAL (los valores de `Motivo` del protocolo)
    [1]       PC (con ILLEGAL, el de la instrucción ilegal)
    [2..33]   x0 … x31
    [34]      K: cantidad de palabras usadas
    [35..]    K pares dirección, dato, en orden de dirección creciente

TIMEOUT no se escribe: un programa que no termina no tiene resultado esperado.
"""

from riscv_toolkit.iss.golden_model import EstadoArquitectonico, Motivo
from riscv_toolkit.protocol import comandos

# Motivo del ISS → código del protocolo, el mismo que reporta el hardware en el snapshot.
_CODIGOS = {
    Motivo.HALTED: comandos.Motivo.HALTED.value,
    Motivo.ILLEGAL: comandos.Motivo.ILLEGAL.value,
}
_MOTIVOS = {codigo: motivo for motivo, codigo in _CODIGOS.items()}
_CABECERA = 2 + 32 + 1  # motivo, PC, registros y K


def a_expected(estado: EstadoArquitectonico) -> str:
    """Texto del `.expected` de `estado`."""
    if estado.motivo not in _CODIGOS:
        raise ValueError(f"no hay resultado esperado para un programa con {estado.motivo.name}")
    renglones = [
        "// estado esperado (golden model, US-108): una palabra por linea, para $readmemh",
        f"{_CODIGOS[estado.motivo]:08x}  // motivo: {estado.motivo.name}",
        f"{estado.pc:08x}  // PC",
    ]
    renglones += [f"{valor:08x}  // x{n}" for n, valor in enumerate(estado.regs)]
    renglones.append(f"{len(estado.mem_usada):08x}  // palabras usadas")
    for direccion, dato in estado.mem_usada.items():
        renglones += [f"{direccion:08x}  // direccion", f"{dato:08x}  // dato"]
    return "\n".join(renglones) + "\n"


def leer_expected(texto: str) -> EstadoArquitectonico:
    """Inversa de `a_expected`. `ValueError` si el texto no tiene el formato."""
    palabras = [
        int(linea.split("//", 1)[0], 16)
        for linea in texto.splitlines()
        if linea.split("//", 1)[0].strip()
    ]
    if len(palabras) < _CABECERA:
        raise ValueError(f"faltan valores: hay {len(palabras)} y la cabecera tiene {_CABECERA}")
    codigo, pc, *resto = palabras
    if codigo not in _MOTIVOS:
        raise ValueError(f"motivo desconocido: {codigo}")
    regs, k, pares = resto[:32], resto[32], resto[33:]
    if len(pares) != 2 * k:
        raise ValueError(f"se esperaban {k} pares dirección/dato y hay {len(pares) / 2:g}")
    mem_usada = dict(zip(pares[::2], pares[1::2], strict=True))
    return EstadoArquitectonico(tuple(regs), mem_usada, pc, _MOTIVOS[codigo])
