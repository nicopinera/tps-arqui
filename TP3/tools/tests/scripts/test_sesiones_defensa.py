from pathlib import Path

from riscv_toolkit.session.export import leer
from scripts.sesiones_defensa import grabar


def test_la_sesion_grabada_se_reabre_con_todos_los_ciclos(tmp_path: Path) -> None:
    destino = tmp_path / "s.json"
    ciclos = grabar("riesgos/06_load_use_stall", destino)
    assert ciclos == 10  # el "# Ciclos: 10" del encabezado
    sesion = leer(destino)
    assert len(list(sesion.historial)) == ciclos + 1  # más el ciclo 0
    assert sesion.historial.indice == 0
