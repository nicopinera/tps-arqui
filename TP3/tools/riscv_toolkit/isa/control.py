"""Unidad de control principal e `imm_gen` del pipeline (agregado US-306, paso 1).

Es el modelo en Python de `hw/rtl/core/control_unit.v` e `imm_gen.v` (US-203): las dos son
**combinacionales** y trabajan en ID. Reciben la palabra de 32 bits que está en IF/ID y
devuelven las señales de control y el inmediato que viajan a ID/EX.

La especificación es `docs/interfaces/tabla_control.md` (US-103): las codificaciones de abajo
son las de su sección 1, y los tests leen su sección 2 fila por fila.

Distinto del golden model (`iss/golden_model.py`): ese decide *qué hace* una instrucción;
esto decide *qué señales prende el hardware* para hacerlo. Por eso hay cosas que el golden
model no necesita y acá sí: `uses_rs1`/`uses_rs2` (para la Hazard Unit), `alu_op`,
`result_src`, `imm_type`.
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Final

from riscv_toolkit.isa.formatos import decode_b, decode_i, decode_j, decode_r, decode_s, decode_u
from riscv_toolkit.isa.instrucciones import HALT_OPCODE

# --- Codificaciones (tabla_control.md §1) -------------------------------------------------
# alu_op: qué le dice la unidad de control a alu_control (EX).
ALU_OP_ADD: Final = 0b00  # loads, stores, jalr: la ALU suma rs1 + imm
ALU_OP_PASS_B: Final = 0b01  # lui: la ALU deja pasar el operando B (el inmediato)
ALU_OP_R: Final = 0b10  # R-type: la operación sale de funct3 + funct7_b5
ALU_OP_I: Final = 0b11  # I aritmético: de funct3 (+ funct7_b5 solo en srai)

# result_src: qué escribe WB en rd.
RESULT_ALU: Final = 0b00
RESULT_MEM: Final = 0b01
RESULT_PC4: Final = 0b10  # jal y jalr: la dirección de vuelta

# imm_type: qué formato de inmediato arma imm_gen.
IMM_I: Final = 0b000
IMM_S: Final = 0b001
IMM_B: Final = 0b010
IMM_U: Final = 0b011
IMM_J: Final = 0b100


@dataclass(frozen=True)
class Control:
    """Las señales de control de una instrucción, como bits (0/1) o campos de 2-3 bits.

    Los valores por defecto (todo en 0) son lo que emite `control_unit.v` para una señal que
    la instrucción no usa (`—` en la tabla). Una burbuja (NOP de hardware) es `Control()`.
    """

    reg_write: int = 0  # escribe rd en WB
    mem_read: int = 0  # load: lee la DMEM en MEM
    mem_write: int = 0  # store: escribe la DMEM en MEM
    result_src: int = RESULT_ALU  # mux de WB
    alu_src: int = 0  # 0: operando B = rs2 · 1: operando B = imm
    alu_op: int = ALU_OP_ADD
    branch: int = 0  # beq/bne: se resuelve en EX
    jump: int = 0  # jal: se resuelve en ID
    jalr: int = 0  # jalr: se resuelve en EX
    imm_type: int = IMM_I
    halt: int = 0  # HALT o ilegal: deja de buscar instrucciones
    illegal: int = 0  # siempre junto con halt = 1
    uses_rs1: int = 0  # lee rs1 de verdad: la Hazard Unit solo mira estos
    uses_rs2: int = 0


# Lo que sale para cualquier palabra que no está en la tabla (tabla_control.md §3).
ILEGAL: Final = Control(halt=1, illegal=1)


# --- Unidad de control -----------------------------------------------------------------------
# Opcodes (tabla_control.md §2).
OP_R: Final = 0b0110011
OP_I: Final = 0b0010011
OP_LOAD: Final = 0b0000011
OP_STORE: Final = 0b0100011
OP_BRANCH: Final = 0b1100011
OP_JALR: Final = 0b1100111
OP_LUI: Final = 0b0110111
OP_JAL: Final = 0b1101111

_F7_CERO, _F7_ALT = 0b0000000, 0b0100000  # funct7 normal / sub, sra, srai

# Opcode → señales. Dentro de un mismo opcode todas las filas de la tabla §2 prenden lo mismo:
# lo que distingue add de sub o lb de lw (funct3, funct7) viaja aparte en ID/EX y lo
# interpretan alu_control (EX) y load_extend (MEM).
_SENALES: Final[dict[int, Control]] = {
    OP_R: Control(reg_write=1, alu_op=ALU_OP_R, uses_rs1=1, uses_rs2=1),
    OP_I: Control(reg_write=1, alu_src=1, alu_op=ALU_OP_I, uses_rs1=1),
    OP_LOAD: Control(reg_write=1, mem_read=1, result_src=RESULT_MEM, alu_src=1, uses_rs1=1),
    # store: la ALU suma rs1 + imm; rs2 no entra a la ALU pero se lee (es el store_data).
    OP_STORE: Control(mem_write=1, alu_src=1, imm_type=IMM_S, uses_rs1=1, uses_rs2=1),
    # branch: no usa la ALU (compara en branch_cmp y suma PC + imm en un sumador propio).
    OP_BRANCH: Control(branch=1, imm_type=IMM_B, uses_rs1=1, uses_rs2=1),
    OP_JALR: Control(reg_write=1, result_src=RESULT_PC4, alu_src=1, jalr=1, uses_rs1=1),
    # lui: rs1 es parte del inmediato, no un registro: uses_rs1 = 0 (sin stalls falsos).
    OP_LUI: Control(reg_write=1, alu_src=1, alu_op=ALU_OP_PASS_B, imm_type=IMM_U),
    OP_JAL: Control(reg_write=1, result_src=RESULT_PC4, jump=1, imm_type=IMM_J),
    HALT_OPCODE: Control(halt=1),  # no lee nada: no provoca stalls (tabla §2)
}


def _legal(opcode: int, funct3: int, funct7: int) -> bool:
    """Si la combinación está en la tabla §3. Un opcode que no está en `_SENALES` no llega."""
    if opcode == OP_R:  # add/sub y srl/sra tienen variante con funct7 = 0100000
        return funct7 == _F7_CERO or (funct7 == _F7_ALT and funct3 in (0b000, 0b101))
    if opcode == OP_I:  # solo los shifts usan funct7; en el resto son bits del inmediato
        if funct3 == 0b001:
            return funct7 == _F7_CERO
        if funct3 == 0b101:
            return funct7 in (_F7_CERO, _F7_ALT)
        return True
    if opcode == OP_LOAD:  # lb, lh, lw, lbu, lhu
        return funct3 in (0b000, 0b001, 0b010, 0b100, 0b101)
    if opcode == OP_STORE:  # sb, sh, sw
        return funct3 in (0b000, 0b001, 0b010)
    if opcode == OP_BRANCH:  # beq, bne (blt… no están implementadas)
        return funct3 in (0b000, 0b001)
    if opcode == OP_JALR:
        return funct3 == 0b000
    return True  # lui, jal y HALT: funct3/funct7 son inmediato o no importan (ADR-004)


def controlar(palabra: int) -> Control:
    """Señales de control de `palabra` (32 bits), según `tabla_control.md` §2 y §3.

    Una palabra que no es una de las 33 instrucciones devuelve `ILEGAL`.

    No usa `identificar()` a propósito: decide la legalidad con su propio caso por opcode,
    como `control_unit.v`. Así el test que compara contra `identificar()` es un control
    independiente y no un error de modo común.
    """
    c = decode_r(palabra)  # opcode, funct3 y funct7 están en el mismo lugar en todo formato
    senales = _SENALES.get(c.opcode)
    if senales is None or not _legal(c.opcode, c.funct3, c.funct7):
        return ILEGAL
    return senales


# --- imm_gen --------------------------------------------------------------------------------
_DECODIFICAR: Final[dict[int, Callable[[int], int]]] = {
    IMM_I: lambda p: decode_i(p).imm,
    IMM_S: lambda p: decode_s(p).imm,
    IMM_B: lambda p: decode_b(p).imm,
    IMM_U: lambda p: decode_u(p).imm,
    IMM_J: lambda p: decode_j(p).imm,
}


def inmediato(palabra: int, imm_type: int) -> int:
    """El inmediato de `palabra` en el formato `imm_type`, extendido a 32 bits **sin signo**.

    Sin signo como lo guarda `ID/EX.imm` (y el golden model): -4 es 0xFFFFFFFC.
    Es `imm_gen.v`: no mira el opcode, solo arma el formato que le pide la unidad de control.
    Un `imm_type` sin usar (101-111) da 0, como el `default` del case en Verilog.
    """
    decodificar = _DECODIFICAR.get(imm_type)
    return decodificar(palabra) & 0xFFFFFFFF if decodificar is not None else 0
