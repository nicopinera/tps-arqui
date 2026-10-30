"""CLI `rvsim`: ensambla un .asm, lo corre en el golden model y muestra el estado final (US-108).

Es el subcomando `sim` de `python -m riscv_toolkit` (se corre desde `TP3/tools/`):

    uv run python -m riscv_toolkit sim programa.asm                     # resumen
    uv run python -m riscv_toolkit sim programa.asm --dump              # registros y memoria usada
    uv run python -m riscv_toolkit sim programa.asm --expect p.expected # para los testbenches

Errores y advertencias van a stderr. Sale con 0 si el programa terminó (HALTED o ILLEGAL: una
ilegal es un resultado válido) y con 1 ante un error de ensamblado o de archivo, o un TIMEOUT.
"""

import argparse
import sys
from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.iss.expected import a_expected
from riscv_toolkit.iss.golden_model import EstadoArquitectonico, GoldenModel, Motivo

_MAX_INSTR = 100_000  # un programa de la suite corre en menos de mil; más es un loop infinito

_EXITO = 0
_ERROR = 1


def agregar_subcomando(
    subcomandos: "argparse._SubParsersAction[argparse.ArgumentParser]",
) -> None:
    """Registra `sim` en el parser de `__main__.py`."""
    parser = subcomandos.add_parser(
        "sim",
        help="corre un .asm en el golden model (rvsim)",
        description="Ensambla un programa, lo corre en el golden model y muestra el estado final.",
    )
    parser.add_argument("entrada", type=Path, help="programa en assembly (.asm)")
    parser.add_argument(
        "--dump", action="store_true", help="muestra los registros y la memoria usada"
    )
    parser.add_argument("--expect", type=Path, help="escribe el estado final en formato .expected")
    parser.add_argument(
        "--max-instr",
        type=int,
        default=_MAX_INSTR,
        help=f"límite de instrucciones antes de cortar con TIMEOUT (por defecto {_MAX_INSTR})",
    )
    parser.set_defaults(ejecutar=ejecutar)


def ejecutar(args: argparse.Namespace) -> int:
    """Ensambla y corre `args.entrada`. Devuelve el código de salida."""
    entrada: Path = args.entrada
    try:
        imagen = ensamblar(entrada.read_text(encoding="utf-8"))
    except OSError as error:
        print(f"{entrada}: error: no se pudo leer: {error.strerror}", file=sys.stderr)
        return _ERROR
    except ErrorEnsamblado as error:
        print(f"{entrada}:{error.linea}: error: {error.mensaje}", file=sys.stderr)
        return _ERROR

    modelo = GoldenModel(imagen.palabras)
    motivo = modelo.run(args.max_instr)
    for advertencia in imagen.advertencias + modelo.advertencias:
        print(f"{entrada}: advertencia: {advertencia}", file=sys.stderr)
    if motivo is Motivo.TIMEOUT:
        print(
            f"{entrada}: error: no terminó en {args.max_instr} instrucciones (TIMEOUT)",
            file=sys.stderr,
        )
        return _ERROR

    estado = modelo.estado_final()
    print(
        f"{entrada}: {motivo.name} en 0x{estado.pc:03x}, "
        f"{modelo.instrucciones_retiradas} instrucciones"
    )
    if args.dump:
        print(_volcado(estado), end="")
    if args.expect is not None:
        try:
            args.expect.write_text(a_expected(estado), encoding="utf-8")
        except OSError as error:
            print(f"{args.expect}: error: no se pudo escribir: {error.strerror}", file=sys.stderr)
            return _ERROR
    return _EXITO


def _volcado(estado: EstadoArquitectonico) -> str:
    """Registros en 4 columnas y las palabras usadas, una por renglón."""
    celdas = [f"x{n:<2} = 0x{valor:08x}" for n, valor in enumerate(estado.regs)]
    renglones = ["   ".join(celdas[i : i + 4]) for i in range(0, 32, 4)]
    renglones.append(f"memoria usada ({len(estado.mem_usada)} palabras):")
    renglones += [f"  0x{d:03x}: 0x{dato:08x}" for d, dato in estado.mem_usada.items()]
    return "\n".join(renglones) + "\n"
