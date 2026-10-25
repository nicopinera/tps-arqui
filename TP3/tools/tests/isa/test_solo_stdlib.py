"""`isa/` no importa nada fuera de la biblioteca estándar (US-105, AC4)."""

import ast
import sys
from pathlib import Path

import pytest

DIR_ISA = Path(__file__).resolve().parents[2] / "riscv_toolkit" / "isa"


def _modulos_importados(archivo: Path) -> set[str]:
    """Nombre completo de cada módulo importado (`from a.b import c` → `a.b`)."""
    arbol = ast.parse(archivo.read_text(encoding="utf-8"))
    modulos: set[str] = set()
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.Import):
            modulos.update(alias.name for alias in nodo.names)
        elif isinstance(nodo, ast.ImportFrom) and nodo.module:
            modulos.add(nodo.module)
    return modulos


def _permitido(modulo: str) -> bool:
    # isa/ puede importarse a sí misma, pero no otras partes del toolkit (protocol/, …).
    return modulo.split(".")[0] in sys.stdlib_module_names or modulo.startswith("riscv_toolkit.isa")


@pytest.mark.parametrize("archivo", sorted(DIR_ISA.glob("*.py")), ids=lambda p: p.name)
def test_isa_solo_importa_stdlib(archivo: Path) -> None:
    prohibidos = {m for m in _modulos_importados(archivo) if not _permitido(m)}
    assert not prohibidos, f"{archivo.name} importa fuera de la stdlib: {prohibidos}"


def test_hay_modulos_que_revisar() -> None:
    # Si la ruta estuviera mal, el test de arriba no tendría casos y pasaría sin probar nada.
    assert {p.name for p in DIR_ISA.glob("*.py")} >= {
        "instrucciones.py",
        "formatos.py",
        "registros.py",
    }
