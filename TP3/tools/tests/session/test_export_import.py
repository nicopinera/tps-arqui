"""Exportar una sesión a JSON y reabrirla (US-505, AC2), y la comparación de Verificar (AC3)."""

import json
from dataclasses import replace
from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.session.debug_session import DebugSession
from riscv_toolkit.session.export import ErrorSesionGuardada, exportar, leer
from riscv_toolkit.session.history import SnapshotHistory
from riscv_toolkit.session.verificar import Diferencia, diferencias, esperado_de

FUENTE = "addi x1, x0, 5\naddi x2, x1, -1\nsw x2, 8(x0)\nhalt\n"
PALABRAS = ensamblar(FUENTE).palabras


@pytest.fixture
def sesion() -> DebugSession:
    """Una sesión con el programa corrido paso a paso hasta HALTED."""
    s = DebugSession(FakeTransport())
    s.load(PALABRAS)
    s.dump()
    while s.step().motivo is None:
        pass
    return s


def test_ac2_ida_y_vuelta_identica(sesion: DebugSession, tmp_path: Path) -> None:
    sesion.historial.ir_a(2)  # mirando un ciclo del medio
    ruta = tmp_path / "sesion.json"
    exportar(ruta, sesion.historial, PALABRAS, FUENTE)

    leida = leer(ruta)
    assert list(leida.historial) == list(sesion.historial)  # snapshots iguales campo a campo
    assert leida.historial.indice == 2
    assert leida.programa == PALABRAS
    assert leida.fuente == FUENTE
    assert all(s.simulado for s in leida.historial)


def test_sin_programa_conocido(sesion: DebugSession, tmp_path: Path) -> None:
    ruta = tmp_path / "s.json"
    exportar(ruta, sesion.historial, None, None)
    leida = leer(ruta)
    assert (leida.programa, leida.fuente) == (None, None)


def _valido(sesion: DebugSession, tmp_path: Path) -> dict[str, object]:
    ruta = tmp_path / "base.json"
    exportar(ruta, sesion.historial, PALABRAS, FUENTE)
    datos: dict[str, object] = json.loads(ruta.read_text(encoding="utf-8"))
    return datos


@pytest.mark.parametrize(
    ("cambio", "mensaje"),
    [
        ({"formato": "otra-cosa"}, "no es una sesión"),
        ({"version": 99}, "versión 99"),
        ({"snapshots": []}, "no tiene snapshots"),
        ({"cursor": 500}, "cursor"),
        ({"programa": [-1]}, "32 bits"),
        ({"fuente": 3}, "texto"),
        ({"snapshots": ["zz"]}, "snapshot 0 está dañado"),
        ({"snapshots": ["0300"]}, "snapshot 0 está dañado"),  # payload corto
    ],
)
def test_archivo_invalido(
    sesion: DebugSession, tmp_path: Path, cambio: dict[str, object], mensaje: str
) -> None:
    datos = {**_valido(sesion, tmp_path), **cambio}
    if cambio.get("snapshots") is not None and "cursor" not in cambio:
        datos["cursor"] = 0
    ruta = tmp_path / "malo.json"
    ruta.write_text(json.dumps(datos), encoding="utf-8")
    with pytest.raises(ErrorSesionGuardada, match=mensaje):
        leer(ruta)


def test_no_es_json(tmp_path: Path) -> None:
    ruta = tmp_path / "x.json"
    ruta.write_text("{roto", encoding="utf-8")
    with pytest.raises(ErrorSesionGuardada, match="No se pudo leer"):
        leer(ruta)


def test_historial_vacio_no_se_puede_reabrir(tmp_path: Path) -> None:
    ruta = tmp_path / "vacio.json"
    exportar(ruta, SnapshotHistory(), PALABRAS, FUENTE)
    with pytest.raises(ErrorSesionGuardada, match="no tiene snapshots"):
        leer(ruta)


# --- Verificar (AC3) -----------------------------------------------------------------------


def test_ac3_coincide_y_alterado_muestra_la_diferencia(sesion: DebugSession) -> None:
    final = sesion.historial.actual
    assert final is not None
    esperado = esperado_de(PALABRAS)
    assert esperado is not None
    assert diferencias(final, esperado) == []

    alterado = replace(final, regs=(0, 7, *final.regs[2:]), mem_usada={0x8: 0})
    assert diferencias(alterado, esperado) == [
        Diferencia("x1", "0x00000007", "0x00000005"),
        Diferencia("[0x008]", "0x00000000", "0x00000004"),
    ]


def test_loop_infinito_no_tiene_esperado() -> None:
    assert esperado_de(ensamblar("loop: jal x0, loop\n").palabras) is None
