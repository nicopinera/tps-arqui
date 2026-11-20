"""Codificación y decodificación de los formatos R, I, S, B, U y J de RV32I (US-105).

Cada `encode_*` recibe los campos de una instrucción y devuelve la palabra de 32 bits; cada
`decode_*` hace lo inverso. El inmediato siempre es el valor real, no el campo crudo.
"""

from dataclasses import dataclass


class ErrorCodificacion(ValueError):  # noqa: N818
    """Un campo no entra en sus bits (registro > 31, inmediato fuera de rango o impar, …)."""


def _verificar(nombre: str, valor: int, minimo: int, maximo: int) -> None:
    """Lanza `ErrorCodificacion` si `valor` no está en `[minimo, maximo]`."""
    if not minimo <= valor <= maximo:
        raise ErrorCodificacion(f"{nombre} fuera de rango: {valor} ({minimo}..{maximo})")


def _campo(palabra: int, pos: int, bits: int) -> int:
    """Extrae `bits` bits de `palabra` empezando en el bit `pos`: `(0x2081B3, 7, 5)` → 3."""
    return (palabra >> pos) & ((1 << bits) - 1)


def sign_extend(valor: int, bits: int) -> int:
    """Interpreta los `bits` bits bajos de `valor` en complemento a dos: `(0xFFF, 12)` → -1."""
    valor &= (1 << bits) - 1
    signo = 1 << (bits - 1)
    # Negativo si el MSB está en 1: restar 2^bits equivale a "negar y sumar 1" con signo menos.
    return valor - (1 << bits) if valor & signo else valor


@dataclass(frozen=True)
class CamposR:
    """Campos de una instrucción registro a registro (add, sub, …). No tiene inmediato."""

    opcode: int
    rd: int
    funct3: int
    rs1: int
    rs2: int
    funct7: int


def encode_r(campos: CamposR) -> int:
    """Palabra de una instrucción R: los seis campos en sus posiciones fijas."""
    _verificar("opcode", campos.opcode, 0, 0x7F)
    _verificar("rd", campos.rd, 0, 31)
    _verificar("funct3", campos.funct3, 0, 0x7)
    _verificar("rs1", campos.rs1, 0, 31)
    _verificar("rs2", campos.rs2, 0, 31)
    _verificar("funct7", campos.funct7, 0, 0x7F)
    rd: int = campos.rd << 7
    funct3: int = campos.funct3 << 12
    rs1: int = campos.rs1 << 15
    rs2: int = campos.rs2 << 20
    funct7: int = campos.funct7 << 25
    resultado: int = campos.opcode | rd | funct3 | rs1 | rs2 | funct7
    return resultado


def decode_r(palabra: int) -> CamposR:
    """Inversa de `encode_r`."""
    return CamposR(
        opcode=_campo(palabra, 0, 7),
        rd=_campo(palabra, 7, 5),
        funct3=_campo(palabra, 12, 3),
        rs1=_campo(palabra, 15, 5),
        rs2=_campo(palabra, 20, 5),
        funct7=_campo(palabra, 25, 7),
    )


@dataclass(frozen=True)
class CamposI:
    """Campos de addi, loads, jalr y shifts. `imm` con signo: -2048..2047.

    En slli/srli/srai el imm lleva el funct7 arriba: `imm = (funct7 << 5) | shamt`.
    """

    opcode: int
    rd: int
    funct3: int
    rs1: int
    imm: int


def encode_i(campos: CamposI) -> int:
    """Palabra de una instrucción I: el inmediato entero va en [31:20]."""
    _verificar("opcode", campos.opcode, 0, 0x7F)
    _verificar("rd", campos.rd, 0, 31)
    _verificar("funct3", campos.funct3, 0, 0x7)
    _verificar("rs1", campos.rs1, 0, 31)
    _verificar("imm", campos.imm, -2048, 2047)
    imm = campos.imm & 0xFFF  # complemento a dos en 12 bits
    return imm << 20 | campos.rs1 << 15 | campos.funct3 << 12 | campos.rd << 7 | campos.opcode


def decode_i(palabra: int) -> CamposI:
    """Inversa de `encode_i`."""
    return CamposI(
        opcode=_campo(palabra, 0, 7),
        rd=_campo(palabra, 7, 5),
        funct3=_campo(palabra, 12, 3),
        rs1=_campo(palabra, 15, 5),
        imm=sign_extend(_campo(palabra, 20, 12), 12),
    )


@dataclass(frozen=True)
class CamposS:
    """Campos de un store (sb, sh, sw). `imm` es el offset con signo: -2048..2047."""

    opcode: int
    funct3: int
    rs1: int
    rs2: int
    imm: int


@dataclass(frozen=True)
class CamposB:
    """Campos de un branch (beq, bne). `imm` es el offset en bytes: par, -4096..4094."""

    opcode: int
    funct3: int
    rs1: int
    rs2: int
    imm: int


@dataclass(frozen=True)
class CamposU:
    """Campos de lui. `imm` es el valor de 32 bits con los 12 bits bajos en 0 (sin signo)."""

    opcode: int
    rd: int
    imm: int


@dataclass(frozen=True)
class CamposJ:
    """Campos de jal. `imm` es el offset en bytes: par, -1048576..1048574 (±1 MiB)."""

    opcode: int
    rd: int
    imm: int


def _verificar_par(nombre: str, valor: int) -> None:
    """B y J no codifican el bit 0 del offset: un valor impar se perdería en silencio."""
    if valor % 2:
        raise ErrorCodificacion(f"{nombre} impar: {valor} (los saltos son a direcciones pares)")


def encode_s(campos: CamposS) -> int:
    """Palabra de un store: el inmediato va partido en [31:25] y [11:7]."""
    _verificar("opcode", campos.opcode, 0, 0x7F)
    _verificar("funct3", campos.funct3, 0, 0x7)
    _verificar("rs1", campos.rs1, 0, 31)
    _verificar("rs2", campos.rs2, 0, 31)
    _verificar("imm", campos.imm, -2048, 2047)
    imm = campos.imm & 0xFFF  # complemento a dos en 12 bits
    return (
        _campo(imm, 5, 7) << 25
        | campos.rs2 << 20
        | campos.rs1 << 15
        | campos.funct3 << 12
        | _campo(imm, 0, 5) << 7
        | campos.opcode
    )


def decode_s(palabra: int) -> CamposS:
    """Inversa de `encode_s`."""
    imm = _campo(palabra, 25, 7) << 5 | _campo(palabra, 7, 5)
    return CamposS(
        opcode=_campo(palabra, 0, 7),
        funct3=_campo(palabra, 12, 3),
        rs1=_campo(palabra, 15, 5),
        rs2=_campo(palabra, 20, 5),
        imm=sign_extend(imm, 12),
    )


def encode_b(campos: CamposB) -> int:
    """Palabra de un branch: imm[12|10:5] en [31:25] e imm[4:1|11] en [11:7]."""
    _verificar("opcode", campos.opcode, 0, 0x7F)
    _verificar("funct3", campos.funct3, 0, 0x7)
    _verificar("rs1", campos.rs1, 0, 31)
    _verificar("rs2", campos.rs2, 0, 31)
    _verificar("imm", campos.imm, -4096, 4094)
    _verificar_par("imm", campos.imm)
    imm = campos.imm & 0x1FFF  # complemento a dos en 13 bits
    return (
        _campo(imm, 12, 1) << 31
        | _campo(imm, 5, 6) << 25
        | campos.rs2 << 20
        | campos.rs1 << 15
        | campos.funct3 << 12
        | _campo(imm, 1, 4) << 8
        | _campo(imm, 11, 1) << 7
        | campos.opcode
    )


def decode_b(palabra: int) -> CamposB:
    """Inversa de `encode_b`; el bit 0 del offset siempre es 0."""
    imm = (
        _campo(palabra, 31, 1) << 12
        | _campo(palabra, 7, 1) << 11
        | _campo(palabra, 25, 6) << 5
        | _campo(palabra, 8, 4) << 1
    )
    return CamposB(
        opcode=_campo(palabra, 0, 7),
        funct3=_campo(palabra, 12, 3),
        rs1=_campo(palabra, 15, 5),
        rs2=_campo(palabra, 20, 5),
        imm=sign_extend(imm, 13),
    )


def encode_u(campos: CamposU) -> int:
    """Palabra de lui: los 20 bits altos del valor van tal cual en [31:12]."""
    _verificar("opcode", campos.opcode, 0, 0x7F)
    _verificar("rd", campos.rd, 0, 31)
    _verificar("imm", campos.imm, 0, 0xFFFFF000)
    if campos.imm & 0xFFF:
        raise ErrorCodificacion(f"imm de U con los 12 bits bajos distintos de 0: {campos.imm:#x}")
    return campos.imm | campos.rd << 7 | campos.opcode


def decode_u(palabra: int) -> CamposU:
    """Inversa de `encode_u`."""
    return CamposU(
        opcode=_campo(palabra, 0, 7),
        rd=_campo(palabra, 7, 5),
        imm=palabra & 0xFFFFF000,
    )


def encode_j(campos: CamposJ) -> int:
    """Palabra de jal: imm[20|10:1|11|19:12] en [31:12]."""
    _verificar("opcode", campos.opcode, 0, 0x7F)
    _verificar("rd", campos.rd, 0, 31)
    _verificar("imm", campos.imm, -(1 << 20), (1 << 20) - 2)
    _verificar_par("imm", campos.imm)
    imm = campos.imm & 0x1FFFFF  # complemento a dos en 21 bits
    return (
        _campo(imm, 20, 1) << 31
        | _campo(imm, 1, 10) << 21
        | _campo(imm, 11, 1) << 20
        | _campo(imm, 12, 8) << 12
        | campos.rd << 7
        | campos.opcode
    )


def decode_j(palabra: int) -> CamposJ:
    """Inversa de `encode_j`; el bit 0 del offset siempre es 0."""
    imm = (
        _campo(palabra, 31, 1) << 20
        | _campo(palabra, 12, 8) << 12
        | _campo(palabra, 20, 1) << 11
        | _campo(palabra, 21, 10) << 1
    )
    return CamposJ(
        opcode=_campo(palabra, 0, 7),
        rd=_campo(palabra, 7, 5),
        imm=sign_extend(imm, 21),
    )
