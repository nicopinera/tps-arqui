"""Tabla de las 33 instrucciones del procesador: lo fijo de cada una (US-105).

Fuente única de verdad para el ensamblador, el desensamblador y el golden model. Los registros
y el inmediato de cada uso no van acá: los arma `formatos.py` con los `Campos*`.
"""

from dataclasses import dataclass
from enum import Enum, auto
from typing import Final

HALT_OPCODE: Final = 0x0B  # opcode custom-0, 0b0001011 (ADR-004)
HALT_WORD: Final = 0x0000000B  # palabra canónica de HALT; también rellena la IMEM (ADR-004)


class Formato(Enum):
    R = auto()
    I = auto()  # noqa: E741
    S = auto()
    B = auto()
    U = auto()
    J = auto()
    HALT = auto()


@dataclass(frozen=True)
class InstructionSpec:
    mnemonico: str
    formato: Formato
    opcode: int
    funct3: int | None = None
    funct7: int | None = None


# (mnemonico, formato, opcode, funct3, funct7), en el orden de la §2.2 del PRD.
_TABLA: list[InstructionSpec] = [
    InstructionSpec("add", Formato.R, 0b0110011, 0b000, 0b0000000),  # rd = rs1 + rs2
    InstructionSpec("sub", Formato.R, 0b0110011, 0b000, 0b0100000),  # rd = rs1 - rs2
    InstructionSpec("sll", Formato.R, 0b0110011, 0b001, 0b0000000),  # shift lógico a izquierda
    InstructionSpec("slt", Formato.R, 0b0110011, 0b010, 0b0000000),  # rd = 1 si rs1 < rs2 (signo)
    InstructionSpec("sltu", Formato.R, 0b0110011, 0b011, 0b0000000),  # ídem, sin signo
    InstructionSpec("xor", Formato.R, 0b0110011, 0b100, 0b0000000),  # xor bit a bit
    InstructionSpec("srl", Formato.R, 0b0110011, 0b101, 0b0000000),  # shift lógico a derecha
    InstructionSpec("sra", Formato.R, 0b0110011, 0b101, 0b0100000),  # shift aritmético a derecha
    InstructionSpec("or", Formato.R, 0b0110011, 0b110, 0b0000000),  # or bit a bit
    InstructionSpec("and", Formato.R, 0b0110011, 0b111, 0b0000000),  # and bit a bit
    InstructionSpec("addi", Formato.I, 0b0010011, 0b000),  # suma con inmediato
    InstructionSpec("slti", Formato.I, 0b0010011, 0b010),  # rd = 1 si rs1 < imm (signo)
    InstructionSpec("sltiu", Formato.I, 0b0010011, 0b011),  # ídem, sin signo
    InstructionSpec("xori", Formato.I, 0b0010011, 0b100),  # xor con inmediato
    InstructionSpec("ori", Formato.I, 0b0010011, 0b110),  # or con inmediato
    InstructionSpec("andi", Formato.I, 0b0010011, 0b111),  # and con inmediato
    InstructionSpec("slli", Formato.I, 0b0010011, 0b001, 0b0000000),  # shift lógico izq. por shamt
    InstructionSpec("srli", Formato.I, 0b0010011, 0b101, 0b0000000),  # shift lógico der. por shamt
    InstructionSpec("srai", Formato.I, 0b0010011, 0b101, 0b0100000),  # shift aritm. der. por shamt
    InstructionSpec("lb", Formato.I, 0b0000011, 0b000),  # carga byte, extiende signo
    InstructionSpec("lh", Formato.I, 0b0000011, 0b001),  # carga media palabra, extiende signo
    InstructionSpec("lw", Formato.I, 0b0000011, 0b010),  # carga palabra
    InstructionSpec("lbu", Formato.I, 0b0000011, 0b100),  # carga byte, extiende con ceros
    InstructionSpec("lhu", Formato.I, 0b0000011, 0b101),  # carga media palabra, con ceros
    InstructionSpec("jalr", Formato.I, 0b1100111, 0b000),  # salta a (rs1 + imm) & ~1, rd = PC + 4
    InstructionSpec("sb", Formato.S, 0b0100011, 0b000),  # guarda byte
    InstructionSpec("sh", Formato.S, 0b0100011, 0b001),  # guarda media palabra
    InstructionSpec("sw", Formato.S, 0b0100011, 0b010),  # guarda palabra
    InstructionSpec("beq", Formato.B, 0b1100011, 0b000),  # salta si rs1 == rs2
    InstructionSpec("bne", Formato.B, 0b1100011, 0b001),  # salta si rs1 != rs2
    InstructionSpec("lui", Formato.U, 0b0110111),  # rd = imm (20 bits altos)
    InstructionSpec("jal", Formato.J, 0b1101111),  # salta a PC + imm, rd = PC + 4
    InstructionSpec("halt", Formato.HALT, HALT_OPCODE),  # detiene el procesador (ADR-004)
]

INSTRUCCIONES: dict[str, InstructionSpec] = {i.mnemonico: i for i in _TABLA}
