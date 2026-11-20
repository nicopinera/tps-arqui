"""SnapshotHistory: lista de snapshots con cursor (US-410)."""

from dataclasses import replace

import pytest

from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    RiesgosCiclo,
    Snapshot,
)
from riscv_toolkit.session.history import SnapshotHistory

BASE = Snapshot(EstadoDU.STEPPING, None, 0, 0, RiesgosCiclo(), (0,) * 32,
                LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB())  # fmt: skip


def con_tres() -> tuple[SnapshotHistory, list[Snapshot]]:
    historial = SnapshotHistory()
    snaps = [replace(BASE, ciclos=c) for c in (1, 2, 3)]
    for s in snaps:
        historial.agregar(s)
    return historial, snaps


def test_vacio() -> None:
    historial = SnapshotHistory()
    assert len(historial) == 0
    assert historial.indice == -1
    assert historial.actual is None
    assert historial.anterior() is None
    assert historial.siguiente() is None


def test_agregar_mueve_el_cursor_al_ultimo() -> None:
    historial, snaps = con_tres()
    assert len(historial) == 3
    assert historial.indice == 2
    assert historial.actual is snaps[2]


def test_navegar() -> None:
    historial, snaps = con_tres()
    assert historial.siguiente() is None  # ya está en el último
    assert historial.anterior() is snaps[1]
    assert historial.anterior() is snaps[0]
    assert historial.anterior() is None
    assert historial.indice == 0
    assert historial.siguiente() is snaps[1]


def test_ir_a_y_negativos() -> None:
    historial, snaps = con_tres()
    assert historial.ir_a(0) is snaps[0]
    assert historial.ir_a(-1) is snaps[2]
    assert historial.indice == 2
    with pytest.raises(IndexError):
        historial.ir_a(3)


def test_agregar_despues_de_volver_atras_salta_al_final() -> None:
    historial, _ = con_tres()
    historial.ir_a(0)
    nuevo = replace(BASE, ciclos=4)
    historial.agregar(nuevo)
    assert historial.actual is nuevo
    assert historial.indice == 3


def test_limpiar() -> None:
    historial, _ = con_tres()
    historial.limpiar()
    assert len(historial) == 0
    assert historial.actual is None


def test_se_recorre_en_orden_de_llegada() -> None:
    historial, snaps = con_tres()
    assert list(historial) == snaps
