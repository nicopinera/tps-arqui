"""Registros y memoria con resaltado de cambios (US-504)."""

from dataclasses import replace

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.session.debug_session import DebugSession
from riscv_toolkit.ui.arquitectura import (
    filas_memoria,
    filas_registros,
    rango_desde_hasta,
    rango_pedido,
)
from tests.ui.test_pipeline import VACIO


def test_ac1_addi_menos_uno_en_los_tres_formatos_y_resaltado() -> None:
    sesion = DebugSession(FakeTransport())
    sesion.load(ensamblar("addi x5, x0, -1\nhalt\n").palabras)
    antes = sesion.dump()
    despues = sesion.step()  # el fake ejecuta una instrucción por paso
    x5 = filas_registros(despues, antes)[5]
    assert (x5.nombre, x5.hexa, x5.con_signo, x5.sin_signo) == (
        "x5", "0xffffffff", "-1", "4294967295",
    )  # fmt: skip
    assert x5.cambio
    assert [f.nombre for f in filas_registros(despues, antes) if f.cambio] == ["x5"]


def test_sin_anterior_no_resalta_y_sin_snapshot_todo_en_cero() -> None:
    s = replace(VACIO, regs=(0, 7, *(0,) * 30))
    assert not any(f.cambio for f in filas_registros(s, None))
    vacias = filas_registros(None, None)
    assert len(vacias) == 32
    assert {f.hexa for f in vacias} == {"0x00000000"}


def test_ac2_sb_resalta_la_palabra_y_el_byte() -> None:
    # sb de 'i' (0x69) en 0x11: el byte +1 de la palabra 0x10, que ya tenía 'H' en +0.
    (fila,) = filas_memoria({0x10: 0x00006948}, {0x10: 0x00000048})
    assert fila.direccion == "0x0010"
    assert fila.bytes_ == ("48", "69", "00", "00")
    assert fila.ascii == "Hi.."
    assert fila.cambio
    assert fila.bytes_cambiados == (False, True, False, False)


def test_palabra_nueva_cuenta_como_cambio_contra_cero() -> None:
    (fila,) = filas_memoria({0x20: 0x41}, {})
    assert fila.bytes_cambiados == (True, False, False, False)


def test_rango_a_pedido_no_resalta_y_va_ordenado() -> None:
    filas = filas_memoria({0x8: 1, 0x0: 2})
    assert [f.direccion for f in filas] == ["0x0000", "0x0008"]
    assert not any(f.cambio for f in filas)


@pytest.mark.parametrize(
    ("direccion", "cantidad", "esperado"),
    [("0x10", "4", (0x10, 4)), ("16", "1", (16, 1)), (" 0x3fc ", "1", (0x3FC, 1))],
)
def test_rango_valido(direccion: str, cantidad: str, esperado: tuple[int, int]) -> None:
    assert rango_pedido(direccion, cantidad) == esperado


@pytest.mark.parametrize(
    ("direccion", "cantidad", "mensaje"),
    [
        ("diez", "4", "números"),
        ("0x11", "1", "alineada"),
        ("-4", "1", "alineada"),
        ("0x0", "0", "DMEM"),
        ("0x3fc", "2", "DMEM"),
    ],
)
def test_rango_invalido(direccion: str, cantidad: str, mensaje: str) -> None:
    with pytest.raises(ValueError, match=mensaje):
        rango_pedido(direccion, cantidad)


def test_rango_desde_hasta() -> None:
    assert rango_desde_hasta("0x0", "0x1c") == (0, 8)
    assert rango_desde_hasta("16", "16") == (16, 1)
    for desde, hasta, mensaje in [
        ("x", "4", "números"),
        ("0x8", "0x4", "mayor"),
        ("0x0", "0x6", "alineada"),
        ("0x0", "0x400", "DMEM"),
    ]:
        with pytest.raises(ValueError, match=mensaje):
            rango_desde_hasta(desde, hasta)
