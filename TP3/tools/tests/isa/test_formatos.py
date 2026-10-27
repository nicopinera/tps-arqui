"""Codificación y decodificación de los formatos RV32I (US-105, AC2 y AC3)."""

from collections.abc import Callable

import pytest

from riscv_toolkit.isa.formatos import (
    CamposB,
    CamposI,
    CamposJ,
    CamposR,
    CamposS,
    CamposU,
    ErrorCodificacion,
    decode_b,
    decode_i,
    decode_j,
    decode_r,
    decode_s,
    decode_u,
    encode_b,
    encode_i,
    encode_j,
    encode_r,
    encode_s,
    encode_u,
    sign_extend,
)

# --- sign_extend ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("valor", "bits", "esperado"),
    [
        (0x000, 12, 0),
        (0x001, 12, 1),
        (0x7FF, 12, 2047),  # máximo positivo de I/S
        (0x800, 12, -2048),  # mínimo de I/S: solo el bit de signo en 1
        (0xFFF, 12, -1),
        (0x0FFE, 13, 4094),  # máximo de B
        (0x1000, 13, -4096),  # mínimo de B
        (0x0FFFFE, 21, 1048574),  # máximo de J
        (0x100000, 21, -1048576),  # mínimo de J
        (0xFFFFFFFF, 32, -1),
    ],
)
def test_sign_extend(valor: int, bits: int, esperado: int) -> None:
    assert sign_extend(valor, bits) == esperado


def test_error_codificacion_es_value_error() -> None:
    # Quien atrape ValueError (sin conocer este módulo) también la atrapa.
    assert issubclass(ErrorCodificacion, ValueError)


# --- Formato R -----------------------------------------------------------------------------

OP_R = 0b0110011

# (campos, palabra) calculadas a mano: verifican la posición de cada campo, no solo la ida y vuelta.
CASOS_R = [
    (CamposR(OP_R, rd=3, funct3=0b000, rs1=1, rs2=2, funct7=0b0000000), 0x002081B3),  # add x3,x1,x2
    (CamposR(OP_R, rd=5, funct3=0b000, rs1=6, rs2=7, funct7=0b0100000), 0x407302B3),  # sub x5,x6,x7
    (CamposR(OP_R, rd=31, funct3=0b111, rs1=31, rs2=31, funct7=0b1111111), 0xFFFFFFB3),  # todo en 1
]


@pytest.mark.parametrize(("campos", "palabra"), CASOS_R)
def test_encode_r(campos: CamposR, palabra: int) -> None:
    assert encode_r(campos) == palabra


@pytest.mark.parametrize(("campos", "palabra"), CASOS_R)
def test_decode_r(campos: CamposR, palabra: int) -> None:
    assert decode_r(palabra) == campos


@pytest.mark.parametrize(
    "campos",
    [
        CamposR(OP_R, rd=0, funct3=0, rs1=0, rs2=0, funct7=0),
        CamposR(OP_R, rd=31, funct3=7, rs1=31, rs2=31, funct7=0x7F),
        CamposR(OP_R, rd=10, funct3=5, rs1=20, rs2=30, funct7=0b0100000),
    ],
)
def test_ida_y_vuelta_r(campos: CamposR) -> None:
    assert decode_r(encode_r(campos)) == campos


@pytest.mark.parametrize(
    ("campos", "campo_malo"),
    [
        (CamposR(0x80, rd=0, funct3=0, rs1=0, rs2=0, funct7=0), "opcode"),
        (CamposR(OP_R, rd=32, funct3=0, rs1=0, rs2=0, funct7=0), "rd"),
        (CamposR(OP_R, rd=0, funct3=8, rs1=0, rs2=0, funct7=0), "funct3"),
        (CamposR(OP_R, rd=0, funct3=0, rs1=-1, rs2=0, funct7=0), "rs1"),
        (CamposR(OP_R, rd=0, funct3=0, rs1=0, rs2=32, funct7=0), "rs2"),
        (CamposR(OP_R, rd=0, funct3=0, rs1=0, rs2=0, funct7=0x80), "funct7"),
    ],
)
def test_encode_r_rechaza_campos_fuera_de_rango(campos: CamposR, campo_malo: str) -> None:
    with pytest.raises(ErrorCodificacion, match=campo_malo):
        encode_r(campos)


# --- Formato I -----------------------------------------------------------------------------

OP_I, OP_LOAD = 0b0010011, 0b0000011


@pytest.mark.parametrize(
    ("campos", "palabra"),
    [
        (CamposI(OP_I, rd=1, funct3=0b000, rs1=0, imm=5), 0x00500093),  # addi x1, x0, 5
        (CamposI(OP_I, rd=1, funct3=0b000, rs1=0, imm=-1), 0xFFF00093),  # addi x1, x0, -1
        (CamposI(OP_LOAD, rd=5, funct3=0b010, rs1=2, imm=-4), 0xFFC12283),  # lw x5, -4(x2)
        # srai x1, x2, 3: el funct7 0100000 viaja dentro del imm (decisión 3).
        (CamposI(OP_I, rd=1, funct3=0b101, rs1=2, imm=(0b0100000 << 5) | 3), 0x40315093),
    ],
)
def test_i(campos: CamposI, palabra: int) -> None:
    assert encode_i(campos) == palabra
    assert decode_i(palabra) == campos


@pytest.mark.parametrize("imm", [-2048, -1, 0, 1, 2047])
def test_ida_y_vuelta_i(imm: int) -> None:
    campos = CamposI(OP_I, rd=31, funct3=0b111, rs1=17, imm=imm)
    assert decode_i(encode_i(campos)) == campos


@pytest.mark.parametrize(
    ("campos", "mensaje"),
    [
        (CamposI(OP_I, rd=1, funct3=0, rs1=0, imm=2048), "imm fuera de rango"),
        (CamposI(OP_I, rd=1, funct3=0, rs1=0, imm=-2049), "imm fuera de rango"),
        (CamposI(OP_I, rd=32, funct3=0, rs1=0, imm=0), "rd fuera de rango"),
        (CamposI(OP_I, rd=1, funct3=8, rs1=0, imm=0), "funct3 fuera de rango"),
    ],
)
def test_encode_i_rechaza(campos: CamposI, mensaje: str) -> None:
    with pytest.raises(ErrorCodificacion, match=mensaje):
        encode_i(campos)


# --- Formatos S, B, U y J --------------------------------------------------------------------
# Palabras verificadas contra una implementación independiente (bits armados como texto).

OP_S, OP_B, OP_U, OP_J = 0b0100011, 0b1100011, 0b0110111, 0b1101111


@pytest.mark.parametrize(
    ("campos", "palabra"),
    [
        (CamposS(OP_S, funct3=0b010, rs1=0, rs2=1, imm=0), 0x00102023),  # sw x1, 0(x0)
        (CamposS(OP_S, funct3=0b010, rs1=2, rs2=5, imm=-4), 0xFE512E23),  # sw x5, -4(x2)
    ],
)
def test_s(campos: CamposS, palabra: int) -> None:
    assert encode_s(campos) == palabra
    assert decode_s(palabra) == campos


@pytest.mark.parametrize(
    ("campos", "palabra"),
    [
        (CamposB(OP_B, funct3=0b000, rs1=0, rs2=0, imm=-4), 0xFE000EE3),  # beq x0, x0, -4
        (CamposB(OP_B, funct3=0b001, rs1=1, rs2=2, imm=8), 0x00209463),  # bne x1, x2, 8
    ],
)
def test_b(campos: CamposB, palabra: int) -> None:
    assert encode_b(campos) == palabra
    assert decode_b(palabra) == campos


def test_u() -> None:
    campos = CamposU(OP_U, rd=1, imm=0x12345000)  # lui x1, 0x12345
    assert encode_u(campos) == 0x123450B7
    assert decode_u(0x123450B7) == campos


@pytest.mark.parametrize(
    ("campos", "palabra"),
    [
        (CamposJ(OP_J, rd=0, imm=0), 0x0000006F),  # jal x0, 0
        (CamposJ(OP_J, rd=1, imm=2048), 0x001000EF),  # jal x1, 2048: solo imm[11]
        (CamposJ(OP_J, rd=1, imm=-4), 0xFFDFF0EF),  # jal x1, -4
    ],
)
def test_j(campos: CamposJ, palabra: int) -> None:
    assert encode_j(campos) == palabra
    assert decode_j(palabra) == campos


# AC2: ida y vuelta con los extremos de cada rango.
@pytest.mark.parametrize("imm", [-2048, -1, 0, 1, 2047])
def test_ida_y_vuelta_s(imm: int) -> None:
    campos = CamposS(OP_S, funct3=0b010, rs1=31, rs2=17, imm=imm)
    assert decode_s(encode_s(campos)) == campos


@pytest.mark.parametrize("imm", [-4096, -2, 0, 2, 2048, 4094])
def test_ida_y_vuelta_b(imm: int) -> None:
    campos = CamposB(OP_B, funct3=0b001, rs1=31, rs2=17, imm=imm)
    assert decode_b(encode_b(campos)) == campos


@pytest.mark.parametrize("imm", [0, 0x1000, 0x7FFFF000, 0x80000000, 0xFFFFF000])
def test_ida_y_vuelta_u(imm: int) -> None:
    campos = CamposU(OP_U, rd=31, imm=imm)
    assert decode_u(encode_u(campos)) == campos


@pytest.mark.parametrize("imm", [-(1 << 20), -2, 0, 2, 2048, (1 << 20) - 2])
def test_ida_y_vuelta_j(imm: int) -> None:
    campos = CamposJ(OP_J, rd=31, imm=imm)
    assert decode_j(encode_j(campos)) == campos


# AC3: rechazos con mensaje claro.
@pytest.mark.parametrize(
    ("codificar", "mensaje"),
    [
        (lambda: encode_s(CamposS(OP_S, 0b010, 0, 0, imm=2048)), "imm fuera de rango"),
        (lambda: encode_s(CamposS(OP_S, 0b010, 0, 32, imm=0)), "rs2 fuera de rango"),
        (lambda: encode_b(CamposB(OP_B, 0b000, 0, 0, imm=3)), "imm impar"),
        (lambda: encode_b(CamposB(OP_B, 0b000, 0, 0, imm=4096)), "imm fuera de rango"),
        (lambda: encode_b(CamposB(OP_B, 0b000, 0, 0, imm=-4098)), "imm fuera de rango"),
        (lambda: encode_u(CamposU(OP_U, 1, imm=0x12345)), "12 bits bajos"),
        (lambda: encode_u(CamposU(OP_U, 1, imm=-0x1000)), "imm fuera de rango"),
        (lambda: encode_j(CamposJ(OP_J, 1, imm=1)), "imm impar"),
        (lambda: encode_j(CamposJ(OP_J, 1, imm=1 << 20)), "imm fuera de rango"),
        (lambda: encode_j(CamposJ(OP_J, 32, imm=0)), "rd fuera de rango"),
    ],
)
def test_encode_rechaza(codificar: Callable[[], int], mensaje: str) -> None:
    with pytest.raises(ErrorCodificacion, match=mensaje):
        codificar()
