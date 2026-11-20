# riscv-toolkit

Software de PC del TP3: ensamblador, desensamblador, golden model, protocolo de la Debug Unit, CLI y GUI.
Se gestiona con [uv](https://docs.astral.sh/uv/):

```bash
uv sync                 # crea el entorno con las dependencias (el proyecto en sí no se instala)
uv run python -m riscv_toolkit   # corre el programa; los subcomandos son asm, sim, dbg y gui
uv run pytest           # tests con cobertura
uv run ruff check .     # lint
uv run ruff format .    # formato
uv run mypy             # tipos (modo estricto)
uv run pip-audit        # vulnerabilidades en dependencias
```

Desde `TP3/`, `make check-py` corre todas las verificaciones juntas.
