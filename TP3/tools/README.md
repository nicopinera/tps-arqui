# riscv-toolkit

Software de PC del TP3: ensamblador, desensamblador, golden model, protocolo de la Debug Unit, CLI y GUI.
Se gestiona con [uv](https://docs.astral.sh/uv/):

```bash
uv sync                 # crea el entorno e instala el proyecto y las herramientas de desarrollo
uv run pytest           # tests con cobertura
uv run ruff check .     # lint
uv run ruff format .    # formato
uv run mypy             # tipos (modo estricto)
uv run pip-audit --skip-editable   # vulnerabilidades en dependencias
```

Desde `TP3/`, `make check-py` corre todas las verificaciones juntas.
