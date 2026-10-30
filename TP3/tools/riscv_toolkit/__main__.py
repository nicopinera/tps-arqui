"""Punto de entrada de `python -m riscv_toolkit`: despacha los subcomandos de `cli/`."""

import argparse
from collections.abc import Callable

from riscv_toolkit.cli import rvasm

# El proyecto no se instala (pyproject: `package = false`), así que no hay metadata de la que
# leer la versión. shortcut: duplicada con `version` de pyproject.toml; mantenerlas iguales.
VERSION = "0.1.0"


def main(argv: list[str] | None = None) -> int:
    """Corre el subcomando de `argv` (por defecto, el de la línea de comandos).

    Sin subcomando muestra la versión. Hoy solo existe `asm`; `sim`, `dbg` y `gui` se agregan
    en sus historias, cada uno con su `agregar_subcomando`.
    """
    parser = argparse.ArgumentParser(
        prog="python -m riscv_toolkit",
        description="Herramientas de PC del procesador RISC-V del TP3.",
    )
    parser.add_argument("--version", action="version", version=f"riscv-toolkit {VERSION}")
    subcomandos = parser.add_subparsers(title="subcomandos")
    rvasm.agregar_subcomando(subcomandos)

    args = parser.parse_args(argv)
    if not hasattr(args, "ejecutar"):
        print(f"riscv-toolkit {VERSION}")
        return 0
    ejecutar: Callable[[argparse.Namespace], int] = args.ejecutar
    return ejecutar(args)


if __name__ == "__main__":
    raise SystemExit(main())
