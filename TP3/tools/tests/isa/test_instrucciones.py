"""La tabla ISA coincide con la §2.2 del PRD (US-105, AC1)."""

import pytest

from riscv_toolkit.isa.instrucciones import (
    _TABLA,
    HALT_OPCODE,
    HALT_WORD,
    INSTRUCCIONES,
    Formato,
)

R, S, B, U, J, HALT = Formato.R, Formato.S, Formato.B, Formato.U, Formato.J, Formato.HALT
I = Formato.I  # noqa: E741 - mismo nombre que en la especificación

# Copiada a mano de la §2.2, en binario como allá, para poder compararla a ojo.
# (formato, opcode, funct3, funct7); None = la instrucción no tiene ese campo.
ESPERADO: dict[str, tuple[Formato, str, str | None, str | None]] = {
    "add": (R, "0110011", "000", "0000000"),
    "sub": (R, "0110011", "000", "0100000"),
    "sll": (R, "0110011", "001", "0000000"),
    "slt": (R, "0110011", "010", "0000000"),
    "sltu": (R, "0110011", "011", "0000000"),
    "xor": (R, "0110011", "100", "0000000"),
    "srl": (R, "0110011", "101", "0000000"),
    "sra": (R, "0110011", "101", "0100000"),
    "or": (R, "0110011", "110", "0000000"),
    "and": (R, "0110011", "111", "0000000"),
    "addi": (I, "0010011", "000", None),
    "slti": (I, "0010011", "010", None),
    "sltiu": (I, "0010011", "011", None),
    "xori": (I, "0010011", "100", None),
    "ori": (I, "0010011", "110", None),
    "andi": (I, "0010011", "111", None),
    "slli": (I, "0010011", "001", "0000000"),
    "srli": (I, "0010011", "101", "0000000"),
    "srai": (I, "0010011", "101", "0100000"),
    "lb": (I, "0000011", "000", None),
    "lh": (I, "0000011", "001", None),
    "lw": (I, "0000011", "010", None),
    "lbu": (I, "0000011", "100", None),
    "lhu": (I, "0000011", "101", None),
    "jalr": (I, "1100111", "000", None),
    "sb": (S, "0100011", "000", None),
    "sh": (S, "0100011", "001", None),
    "sw": (S, "0100011", "010", None),
    "beq": (B, "1100011", "000", None),
    "bne": (B, "1100011", "001", None),
    "lui": (U, "0110111", None, None),
    "jal": (J, "1101111", None, None),
    "halt": (HALT, "0001011", None, None),
}


def _bin(campo: str | None) -> int | None:
    return None if campo is None else int(campo, 2)


def test_tabla_completa() -> None:
    assert len(INSTRUCCIONES) == 33
    assert INSTRUCCIONES.keys() == ESPERADO.keys()


def test_sin_mnemonicos_repetidos() -> None:
    # Un repetido no da error: el dict se queda con la última fila y la primera se pierde.
    assert len(_TABLA) == len(INSTRUCCIONES)


@pytest.mark.parametrize("mnemonico", ESPERADO)
def test_valores_de_la_seccion_2_2(mnemonico: str) -> None:
    formato, opcode, funct3, funct7 = ESPERADO[mnemonico]
    spec = INSTRUCCIONES[mnemonico]
    assert spec.mnemonico == mnemonico
    assert spec.formato is formato
    assert spec.opcode == _bin(opcode)
    assert spec.funct3 == _bin(funct3)
    assert spec.funct7 == _bin(funct7)


def test_halt_es_coherente() -> None:
    assert INSTRUCCIONES["halt"].opcode == HALT_OPCODE
    assert HALT_WORD & 0x7F == HALT_OPCODE
