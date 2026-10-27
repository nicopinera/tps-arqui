"""Punto de entrada de `python -m riscv_toolkit`."""

# El proyecto no se instala (pyproject: `package = false`), así que no hay metadata de la que
# leer la versión. shortcut: duplicada con `version` de pyproject.toml; mantenerlas iguales.
VERSION = "0.1.0"


def main() -> int:
    """Muestra la versión; los subcomandos (asm, sim, dbg, gui) se agregan en sus historias."""
    print(f"riscv-toolkit {VERSION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
