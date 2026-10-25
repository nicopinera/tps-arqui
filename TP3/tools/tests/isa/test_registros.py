"""Nombres de registros: solo `x0`…`x31` (US-105, ADR-013)."""

import pytest

from riscv_toolkit.isa.registros import REGISTROS


def test_hay_32_registros() -> None:
    assert len(REGISTROS) == 32


def test_extremos() -> None:
    assert REGISTROS["x0"] == 0
    assert REGISTROS["x31"] == 31


@pytest.mark.parametrize("n", range(32))
def test_cada_nombre_da_su_numero(n: int) -> None:
    assert REGISTROS[f"x{n}"] == n


@pytest.mark.parametrize("nombre", ["x32", "t0", "sp", "zero", "X5", "x05"])
def test_nombres_no_aceptados(nombre: str) -> None:
    assert nombre not in REGISTROS
