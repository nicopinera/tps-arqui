"""Formato `.expected` (US-108, AC6)."""

import pytest

from riscv_toolkit.iss.expected import a_expected, leer_expected
from riscv_toolkit.iss.golden_model import EstadoArquitectonico, Motivo

ESTADO = EstadoArquitectonico(
    regs=(0, 0xFFFFFFFF, 55) + (0,) * 29,
    mem_usada={0x20: 55, 0x3FC: 1},
    pc=0x1C,
    motivo=Motivo.HALTED,
)


def test_ida_y_vuelta() -> None:
    assert leer_expected(a_expected(ESTADO)) == ESTADO


def test_ida_y_vuelta_ilegal_sin_memoria() -> None:
    estado = EstadoArquitectonico((0,) * 32, {}, 0x08, Motivo.ILLEGAL)
    assert leer_expected(a_expected(estado)) == estado


def test_layout() -> None:
    valores = [linea.split("//")[0].strip() for linea in a_expected(ESTADO).splitlines()[1:]]
    assert valores[0] == "00000001"  # motivo HALTED, como en el protocolo
    assert valores[1] == "0000001c"  # PC
    assert valores[2:5] == ["00000000", "ffffffff", "00000037"]  # x0, x1, x2
    assert valores[34] == "00000002"  # K
    assert valores[35:] == ["00000020", "00000037", "000003fc", "00000001"]
    assert all(len(v) == 8 for v in valores)  # $readmemh: una palabra de 32 bits por línea


def test_timeout_no_tiene_expected() -> None:
    with pytest.raises(ValueError, match="TIMEOUT"):
        a_expected(EstadoArquitectonico((0,) * 32, {}, 0, Motivo.TIMEOUT))


@pytest.mark.parametrize(
    ("texto", "error"),
    [
        ("00000001\n", "faltan valores"),
        ("00000007\n" + "00000000\n" * 34, "motivo desconocido"),
        ("00000001\n" + "00000000\n" * 32 + "00000001\n00000020\n", "pares"),
    ],
)
def test_texto_mal_formado(texto: str, error: str) -> None:
    with pytest.raises(ValueError, match=error):
        leer_expected(texto)
