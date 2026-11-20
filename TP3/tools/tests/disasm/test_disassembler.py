"""Desensamblador (US-107, AC1 y AC2)."""

from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.disasm.disassembler import desensamblar
from riscv_toolkit.isa.instrucciones import HALT_WORD, INSTRUCCIONES, Formato

FIXTURE = Path(__file__).parents[1] / "assembler" / "fixtures" / "todas_las_instrucciones.asm"

_SALTOS = {m for m, spec in INSTRUCCIONES.items() if spec.formato in (Formato.B, Formato.J)}


def _reensamblar(palabras: list[int]) -> list[int]:
    """Desensambla con el PC de cada palabra y vuelve a ensamblar.

    Los destinos de branches y `jal` salen como dirección (`0x1c`) y el ensamblador solo acepta
    etiquetas: cada línea lleva la etiqueta `L<dirección>` y los destinos se reemplazan por ella.
    """
    lineas = []
    for i, palabra in enumerate(palabras):
        texto = desensamblar(palabra, pc=4 * i)
        if texto.split()[0] in _SALTOS:
            cuerpo, destino = texto.rsplit(", ", 1)
            texto = f"{cuerpo}, L{int(destino, 16)}"
        lineas.append(f"L{4 * i}: {texto}")
    return ensamblar("\n".join(lineas)).palabras


# --- AC1: ida y vuelta -------------------------------------------------------------------------


def test_ida_y_vuelta_de_las_33() -> None:
    # El fixture tiene las 32 estándar; el ensamblador le agrega el halt.
    palabras = ensamblar(FIXTURE.read_text(encoding="utf-8")).palabras
    usadas = {desensamblar(p).split()[0] for p in palabras}
    assert usadas == set(INSTRUCCIONES)
    assert _reensamblar(palabras) == palabras


@pytest.mark.parametrize(
    ("palabra", "texto"),
    [
        (0x00A28293, "addi x5, x5, 10"),  # el ejemplo del PRD
        (0x41DF0FB3, "sub x31, x30, x29"),
        (0x80000093, "addi x1, x0, -2048"),  # extremos del imm de 12 bits
        (0x7FF0A113, "slti x2, x1, 2047"),
        (0xFFF13193, "sltiu x3, x2, -1"),  # sltiu también extiende con signo
        (0x01F35413, "srli x8, x6, 31"),
        (0x41145493, "srai x9, x8, 17"),  # el funct7 de srai no se mezcla con el shamt
        (0xFFF10503, "lb x10, -1(x2)"),
        (0x80052603, "lw x12, -2048(x10)"),
        (0x004280E7, "jalr x1, 4(x5)"),
        (0xFEF10FA3, "sb x15, -1(x2)"),  # S: el dato (rs2) va primero
        (0x00000FB7, "lui x31, 0x0"),
        (0xFFFFF9B7, "lui x19, 0xfffff"),  # los 20 bits altos, no el valor de 32
        (0x12345A37, "lui x20, 0x12345"),
    ],
)
def test_texto(palabra: int, texto: str) -> None:
    assert desensamblar(palabra) == texto


# --- Destinos de branches y jal ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("palabra", "pc", "texto"),
    [
        (0xFC208EE3, None, "beq x1, x2, .-36"),  # hacia atrás
        (0xFC208EE3, 0x24, "beq x1, x2, 0x0"),
        (0x00419463, None, "bne x3, x4, .+8"),  # hacia adelante
        (0x00419463, 0x28, "bne x3, x4, 0x30"),
        (0xFD1FF0EF, 0x30, "jal x1, 0x0"),
        (0x0080006F, None, "jal x0, .+8"),
    ],
)
def test_destino_de_saltos(palabra: int, pc: int | None, texto: str) -> None:
    assert desensamblar(palabra, pc) == texto


# --- halt e ilegales (AC2) ---------------------------------------------------------------------


@pytest.mark.parametrize("palabra", [HALT_WORD, 0xFFFFF00B, 0x0000708B])
def test_cualquier_custom0_es_halt(palabra: int) -> None:
    # ADR-004: se detecta solo por el opcode, el resto de los bits no importa.
    assert desensamblar(palabra) == "halt"


# Los casos de tabla_control.md §3 ("Casos ilegales que conviene probar").
ILEGALES = [
    0x00000000,  # opcode 0000000
    0xFFFFFFFF,  # opcode 1111111
    0x003120E3,  # branch con funct3 = 010
    0x003140E3,  # blt (funct3 = 100): RV32I, pero no implementada
    0x00313083,  # load con funct3 = 011 (ld)
    0x00316083,  # load con funct3 = 110 (lwu)
    0x003130A3,  # store con funct3 = 011 (sd)
    0x02311093,  # slli con funct7 = 0000001
    0x02315093,  # srli con funct7 = 0000001
    0x023100B3,  # mul: R con funct7 = 0000001 (extensión M)
    0x403110B3,  # funct7 = 0100000 con funct3 = 001: solo sub y sra lo usan
    0x003110E7,  # jalr con funct3 = 001
    0x00001097,  # auipc
    0x00000073,  # ecall
    0x0000000F,  # fence
]


@pytest.mark.parametrize("palabra", ILEGALES)
def test_ilegal_sale_como_word(palabra: int) -> None:
    texto = desensamblar(palabra)
    assert texto == f".word 0x{palabra:08x}"
    assert ensamblar(texto).palabras[0] == palabra  # también tiene ida y vuelta


@pytest.mark.parametrize("palabra", [-1, 0x1_0000_0000])
def test_palabra_fuera_de_32_bits(palabra: int) -> None:
    with pytest.raises(ValueError, match="32 bits"):
        desensamblar(palabra)
