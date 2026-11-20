"""Unidad de control e imm_gen contra `docs/interfaces/tabla_control.md` (US-306, paso 1).

La tabla se lee del .md: es la misma que va a usar `tb_control_unit.v`, así que si alguien la
cambia, este test lo nota. Una celda `—` no se verifica (la señal no se usa en esa fila).
"""

import random
import re
from dataclasses import fields
from pathlib import Path

import pytest

from riscv_toolkit.isa.control import (
    ILEGAL,
    IMM_B,
    IMM_I,
    IMM_J,
    IMM_S,
    IMM_U,
    Control,
    controlar,
    inmediato,
)
from riscv_toolkit.isa.formatos import (
    CamposB,
    CamposI,
    CamposJ,
    CamposS,
    CamposU,
    encode_b,
    encode_i,
    encode_j,
    encode_s,
    encode_u,
)
from riscv_toolkit.isa.instrucciones import HALT_OPCODE, identificar

TABLA = Path(__file__).resolve().parents[4] / "docs" / "interfaces" / "tabla_control.md"
# Columnas de la §2, en orden, después de #, instrucción, opcode, funct3 y funct7.
SENALES = (
    "reg_write", "mem_read", "mem_write", "result_src", "alu_src", "alu_op", "branch", "jump",
    "jalr", "imm_type", "halt", "uses_rs1", "uses_rs2",
)  # fmt: skip
RD, RS1, RS2 = 1, 2, 3  # registros cualesquiera para armar la palabra de cada fila


def _bits(celda: str) -> int | None:
    """ "`01` MEM" → 1; "1" → 1; "—" → None (no se verifica)."""
    m = re.search(r"[01]+", celda)
    return None if "—" in celda or m is None else int(m.group(), 2)


def _filas() -> list[tuple[str, int, dict[str, int]]]:
    """(mnemónico, palabra, señales esperadas) de cada una de las 33 filas."""
    filas = []
    for linea in TABLA.read_text(encoding="utf-8").splitlines():
        celdas = [c.strip() for c in linea.strip().strip("|").split("|")]
        if not celdas[0].isdigit():
            continue
        nombre = celdas[1].strip("`")
        opcode, funct3, funct7 = (_bits(c) or 0 for c in celdas[2:5])
        palabra = (
            funct7 << 25 | RS2 << 20 | RS1 << 15 | funct3 << 12 | RD << 7 | opcode
        )  # fmt: skip
        esperadas = {
            s: v for s, c in zip(SENALES, celdas[5:], strict=True) if (v := _bits(c)) is not None
        }
        filas.append((nombre, palabra, esperadas))
    return filas


FILAS = _filas()


def test_la_tabla_tiene_las_33_instrucciones() -> None:
    assert len(FILAS) == 33
    # Cada palabra armada es la instrucción de su fila (si no, el test probaría otra cosa).
    for nombre, palabra, _ in FILAS:
        spec = identificar(palabra)
        assert spec is not None, nombre
        assert spec.mnemonico == nombre


@pytest.mark.parametrize(("nombre", "palabra", "esperadas"), FILAS, ids=[f[0] for f in FILAS])
def test_senales_de_cada_instruccion(nombre: str, palabra: int, esperadas: dict[str, int]) -> None:
    control = controlar(palabra)
    obtenidas = {s: getattr(control, s) for s in esperadas}
    assert obtenidas == esperadas
    assert control.illegal == 0


def test_las_senales_no_dependen_de_los_registros() -> None:
    # La unidad de control mira opcode/funct3/funct7, nunca rd, rs1 ni rs2.
    for _, palabra, _ in FILAS:
        otros = palabra ^ (0b11111 << 7) ^ (0b11111 << 15) ^ (0b11111 << 20)
        if identificar(otros) == identificar(palabra):  # en I/U/J esos bits son del imm
            assert controlar(otros) == controlar(palabra)


@pytest.mark.parametrize(
    "palabra",
    [
        0x00000000,  # opcode 0000000
        0xFFFFFFFF,  # opcode 1111111
        0x0020A063 | 0b010 << 12,  # branch con funct3 = 010
        0x0020C063,  # blt: RV32I pero no implementada
        0x0000B083,  # load con funct3 = 011 (ld)
        0x0000E083,  # load con funct3 = 110 (lwu)
        0x0010B023,  # store con funct3 = 011
        0x02009093,  # slli con funct7 = 0000001
        0x022081B3,  # mul (extensión M)
        0x000090E7,  # jalr con funct3 = 001
        0x00000097,  # auipc
        0x00000073,  # ecall
        0x0000000F,  # fence
    ],
    ids=lambda p: f"0x{p:08x}",
)
def test_palabras_ilegales(palabra: int) -> None:
    assert identificar(palabra) is None  # el caso de verdad es ilegal
    assert controlar(palabra) == ILEGAL


def test_halt_se_detecta_solo_por_opcode() -> None:
    # ADR-004: cualquier palabra con opcode custom-0 es HALT, tenga lo que tenga arriba.
    for arriba in (0, 0xFFFFF, 0x12345):
        assert controlar(arriba << 12 | 0b11111 << 7 | HALT_OPCODE) == Control(halt=1)


def test_ilegal_coincide_con_identificar() -> None:
    # Muchas palabras al azar, con opcodes reales para que no sean casi todas ilegales.
    opcodes = [0x33, 0x13, 0x03, 0x23, 0x63, 0x67, 0x6F, 0x37, HALT_OPCODE, 0x17, 0x73]
    azar = random.Random(306)  # noqa: S311 - reproducible, no es criptografía
    for _ in range(3000):
        palabra = azar.getrandbits(25) << 7 | azar.choice(opcodes)
        assert controlar(palabra).illegal == (identificar(palabra) is None), f"0x{palabra:08x}"


def test_imm_type_sin_usar_da_cero() -> None:
    assert inmediato(0xFFFFFFFF, 0b101) == 0


def test_ilegal_no_escribe_ni_lee_nada() -> None:
    assert {f.name for f in fields(ILEGAL) if getattr(ILEGAL, f.name)} == {"halt", "illegal"}


# --- imm_gen --------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("palabra", "imm_type", "esperado"),
    [
        (encode_i(CamposI(0x13, 1, 0, 2, -5)), IMM_I, 0xFFFFFFFB),  # addi x1, x2, -5
        (encode_i(CamposI(0x13, 1, 0, 2, 2047)), IMM_I, 0x7FF),  # máximo
        (encode_i(CamposI(0x13, 1, 0, 2, -2048)), IMM_I, 0xFFFFF800),  # mínimo
        (encode_s(CamposS(0x23, 0b010, 2, 1, -4)), IMM_S, 0xFFFFFFFC),  # sw x1, -4(x2)
        (encode_s(CamposS(0x23, 0b010, 2, 1, 2047)), IMM_S, 0x7FF),
        (encode_b(CamposB(0x63, 0, 1, 2, -8)), IMM_B, 0xFFFFFFF8),  # beq hacia atrás
        (encode_b(CamposB(0x63, 0, 1, 2, 4094)), IMM_B, 0xFFE),  # bit 11 en su lugar raro
        (encode_b(CamposB(0x63, 0, 1, 2, -4096)), IMM_B, 0xFFFFF000),
        (encode_u(CamposU(0x37, 1, 0x12345000)), IMM_U, 0x12345000),  # lui x1, 0x12345
        (encode_u(CamposU(0x37, 1, 0xFFFFF000)), IMM_U, 0xFFFFF000),  # U no se extiende
        (encode_j(CamposJ(0x6F, 1, 2048)), IMM_J, 0x800),  # jal: bit 11 en el lugar 20
        (encode_j(CamposJ(0x6F, 1, -1048576)), IMM_J, 0xFFF00000),
    ],
)
def test_imm_gen(palabra: int, imm_type: int, esperado: int) -> None:
    assert inmediato(palabra, imm_type) == esperado


def test_imm_gen_usa_el_formato_que_le_pide_control() -> None:
    # De punta a punta: el imm_type que da controlar() arma el inmediato correcto.
    sw = encode_s(CamposS(0x23, 0b010, 2, 1, -4))
    assert inmediato(sw, controlar(sw).imm_type) == 0xFFFFFFFC
