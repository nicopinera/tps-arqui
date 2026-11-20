"""diff(a, b): registros, memoria y PC que cambiaron (US-410)."""

from dataclasses import replace

from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    RiesgosCiclo,
    Snapshot,
)
from riscv_toolkit.session.diff import diff

A = Snapshot(EstadoDU.STEPPING, None, 1, 0x10, RiesgosCiclo(), (0, 5) + (0,) * 30,
             LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB(), {0x20: 7, 0x24: 1})  # fmt: skip


def test_sin_cambios() -> None:
    cambios = diff(A, replace(A, ciclos=2, if_id=LatchIFID(valid=True)))  # latches no cuentan
    assert not cambios
    assert cambios.pc is None
    assert cambios.regs == {}
    assert cambios.memoria == {}


def test_pc_y_registros() -> None:
    b = replace(A, pc=0x14, regs=(0, 6, 9) + (0,) * 29)
    cambios = diff(A, b)
    assert cambios
    assert cambios.pc == (0x10, 0x14)
    assert cambios.regs == {1: (5, 6), 2: (0, 9)}


def test_memoria_nueva_cambiada_y_ausente_vale_cero() -> None:
    b = replace(A, mem_usada={0x20: 8, 0x24: 1, 0x28: 3, 0x2C: 0})
    cambios = diff(A, b)
    # 0x20 cambió, 0x28 es nueva; 0x2C se escribió con 0 donde había 0: no es un cambio.
    assert cambios.memoria == {0x20: (7, 8), 0x28: (0, 3)}
    assert cambios.pc is None
