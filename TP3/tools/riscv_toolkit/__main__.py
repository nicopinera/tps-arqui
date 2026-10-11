"""Punto de entrada de `python -m riscv_toolkit`."""

from importlib.metadata import version


def main() -> int:
    """Muestra la versión instalada; los comandos reales se agregan en las historias siguientes."""
    print(f"riscv-toolkit {version('riscv-toolkit')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
