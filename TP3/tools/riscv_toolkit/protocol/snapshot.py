"""Payloads `SNAPSHOT` y `MEM_DATA` como objetos con nombre (US-409, ADR-017, protocolo §6.2).

`Snapshot.from_bytes` es el espejo del `du_dumper`: recorre el payload en el mismo orden en que
el hardware lo arma. `to_bytes` hace lo inverso (lo usa `FakeTransport` para responder igual que
la placa) y sirve para probar que la ida y la vuelta coinciden.

Los valores de 32 bits (registros, PC, `imm`, …) se guardan sin signo, como en el golden model;
para verlos con signo, `isa.formatos.sign_extend(valor, 32)`.
"""

import struct
from dataclasses import dataclass, field
from typing import Self

from riscv_toolkit.protocol.codec import ErrorLongitud, ErrorPayload
from riscv_toolkit.protocol.comandos import (
    SNAP_CABECERA,
    SNAP_EX_MEM,
    SNAP_ID_EX,
    SNAP_IF_ID,
    SNAP_MEM_WB,
    SNAP_RIESGOS,
    SNAPSHOT_FIJO,
    EstadoDU,
    Motivo,
)

_NIBBLE = 0xF
_REGS = 32

# Formatos de `struct`: `<` = little-endian sin relleno, I = 4 B, H = 2 B, B = 1 B.
_FMT_CABECERA = "<BIIB"  # estado, ciclos, PC, riesgos
_FMT_REGS = f"<{_REGS}I"
_FMT_IF_ID = "<IIIB"  # pc, pc_plus4, instr, flags
_FMT_ID_EX = "<IIIIIBBBBBBBI"  # pc … imm, rs1, rs2, rd, funct3, alu_op, flags1, flags2, instr
_FMT_EX_MEM = "<IIIBBBI"  # alu_result, store_data, pc_plus4, rd, funct3, flags, instr
_FMT_MEM_WB = "<IIIBBI"  # alu_result, mem_data, pc_plus4, rd, flags, instr
_FMT_USADA = "<HI"  # dirección en bytes, dato

# Offsets del payload (protocolo §6.2), derivados de los tamaños de `comandos.py`.
_OFF_REGS = SNAP_CABECERA + SNAP_RIESGOS  # 10
_OFF_IF_ID = _OFF_REGS + struct.calcsize(_FMT_REGS)  # 138
_OFF_ID_EX = _OFF_IF_ID + SNAP_IF_ID  # 151
_OFF_EX_MEM = _OFF_ID_EX + SNAP_ID_EX  # 182
_OFF_MEM_WB = _OFF_EX_MEM + SNAP_EX_MEM  # 201
_OFF_K = _OFF_MEM_WB + SNAP_MEM_WB  # 219


def _bit(byte: int, n: int) -> bool:
    return bool((byte >> n) & 1)


def _campo(byte: int, n: int, bits: int) -> int:
    return (byte >> n) & ((1 << bits) - 1)


def _flags(*bits: bool) -> int:
    """Byte con `bits[0]` en el bit 0, `bits[1]` en el bit 1, …"""
    return sum(int(b) << n for n, b in enumerate(bits))


@dataclass(frozen=True)
class RiesgosCiclo:
    """Byte de riesgos (offset 9): qué hizo la Hazard Unit y la Forwarding Unit en este ciclo."""

    stall: bool = False
    flush_if_id: bool = False
    flush_id_ex: bool = False
    fwd_a: int = 0  # 0 = banco de registros, 1 = desde MEM/WB, 2 = desde EX/MEM
    fwd_b: int = 0

    @classmethod
    def from_byte(cls, b: int) -> Self:
        return cls(_bit(b, 0), _bit(b, 1), _bit(b, 2), _campo(b, 3, 2), _campo(b, 5, 2))

    def to_byte(self) -> int:
        return _flags(self.stall, self.flush_if_id, self.flush_id_ex) | (
            self.fwd_a << 3 | self.fwd_b << 5
        )


@dataclass(frozen=True)
class LatchIFID:
    pc: int = 0
    pc_plus4: int = 0
    instr: int = 0
    valid: bool = False

    @classmethod
    def from_bytes(cls, datos: bytes) -> Self:
        pc, pc_plus4, instr, flags = struct.unpack(_FMT_IF_ID, datos)
        return cls(pc, pc_plus4, instr, _bit(flags, 0))

    def to_bytes(self) -> bytes:
        return struct.pack(_FMT_IF_ID, self.pc, self.pc_plus4, self.instr, int(self.valid))


@dataclass(frozen=True)
class LatchIDEX:
    pc: int = 0
    pc_plus4: int = 0
    rs1_data: int = 0
    rs2_data: int = 0
    imm: int = 0
    rs1: int = 0
    rs2: int = 0
    rd: int = 0
    funct3: int = 0
    alu_op: int = 0
    valid: bool = False
    reg_write: bool = False
    mem_read: bool = False
    mem_write: bool = False
    alu_src: bool = False
    branch: bool = False
    jump: bool = False
    jalr: bool = False
    halt: bool = False
    illegal: bool = False
    funct7_b5: bool = False
    result_src: int = 0
    instr: int = 0

    @classmethod
    def from_bytes(cls, datos: bytes) -> Self:
        (pc, pc4, rs1_d, rs2_d, imm, rs1, rs2, rd, f3, alu_op, f1, f2, instr) = struct.unpack(
            _FMT_ID_EX, datos
        )
        return cls(
            pc=pc, pc_plus4=pc4, rs1_data=rs1_d, rs2_data=rs2_d, imm=imm,
            rs1=rs1, rs2=rs2, rd=rd, funct3=f3, alu_op=alu_op,
            valid=_bit(f1, 0), reg_write=_bit(f1, 1), mem_read=_bit(f1, 2),
            mem_write=_bit(f1, 3), alu_src=_bit(f1, 4), branch=_bit(f1, 5),
            jump=_bit(f1, 6), jalr=_bit(f1, 7),
            halt=_bit(f2, 0), illegal=_bit(f2, 1), funct7_b5=_bit(f2, 2),
            result_src=_campo(f2, 3, 2), instr=instr,
        )  # fmt: skip

    def to_bytes(self) -> bytes:
        flags1 = _flags(
            self.valid, self.reg_write, self.mem_read, self.mem_write,
            self.alu_src, self.branch, self.jump, self.jalr,
        )  # fmt: skip
        flags2 = _flags(self.halt, self.illegal, self.funct7_b5) | self.result_src << 3
        return struct.pack(
            _FMT_ID_EX, self.pc, self.pc_plus4, self.rs1_data, self.rs2_data, self.imm,
            self.rs1, self.rs2, self.rd, self.funct3, self.alu_op, flags1, flags2, self.instr,
        )  # fmt: skip


@dataclass(frozen=True)
class LatchEXMEM:
    alu_result: int = 0
    store_data: int = 0
    pc_plus4: int = 0
    rd: int = 0
    funct3: int = 0
    valid: bool = False
    halt: bool = False
    illegal: bool = False
    reg_write: bool = False
    mem_read: bool = False
    mem_write: bool = False
    result_src: int = 0
    instr: int = 0

    @classmethod
    def from_bytes(cls, datos: bytes) -> Self:
        alu, store, pc4, rd, f3, fl, instr = struct.unpack(_FMT_EX_MEM, datos)
        return cls(
            alu_result=alu, store_data=store, pc_plus4=pc4, rd=rd, funct3=f3,
            valid=_bit(fl, 0), halt=_bit(fl, 1), illegal=_bit(fl, 2),
            reg_write=_bit(fl, 3), mem_read=_bit(fl, 4), mem_write=_bit(fl, 5),
            result_src=_campo(fl, 6, 2), instr=instr,
        )  # fmt: skip

    def to_bytes(self) -> bytes:
        fl = _flags(
            self.valid, self.halt, self.illegal, self.reg_write, self.mem_read, self.mem_write
        ) | (self.result_src << 6)
        return struct.pack(
            _FMT_EX_MEM, self.alu_result, self.store_data, self.pc_plus4, self.rd, self.funct3,
            fl, self.instr,
        )  # fmt: skip


@dataclass(frozen=True)
class LatchMEMWB:
    alu_result: int = 0
    mem_data: int = 0
    pc_plus4: int = 0
    rd: int = 0
    valid: bool = False
    halt: bool = False
    illegal: bool = False
    reg_write: bool = False
    result_src: int = 0
    instr: int = 0

    @classmethod
    def from_bytes(cls, datos: bytes) -> Self:
        alu, mem, pc4, rd, fl, instr = struct.unpack(_FMT_MEM_WB, datos)
        return cls(
            alu_result=alu, mem_data=mem, pc_plus4=pc4, rd=rd,
            valid=_bit(fl, 0), halt=_bit(fl, 1), illegal=_bit(fl, 2), reg_write=_bit(fl, 3),
            result_src=_campo(fl, 4, 2), instr=instr,
        )  # fmt: skip

    def to_bytes(self) -> bytes:
        fl = _flags(self.valid, self.halt, self.illegal, self.reg_write) | (self.result_src << 4)
        return struct.pack(
            _FMT_MEM_WB, self.alu_result, self.mem_data, self.pc_plus4, self.rd, fl, self.instr
        )


@dataclass(frozen=True)
class Snapshot:
    """Estado completo del procesador en un ciclo (payload de la trama `SNAPSHOT`)."""

    estado: EstadoDU
    motivo: Motivo | None  # HALTED / ILLEGAL / ABORTED, o None si la ejecución no terminó
    ciclos: int
    pc: int
    riesgos: RiesgosCiclo
    regs: tuple[int, ...]  # x0 … x31, sin signo
    if_id: LatchIFID
    id_ex: LatchIDEX
    ex_mem: LatchEXMEM
    mem_wb: LatchMEMWB
    mem_usada: dict[int, int] = field(default_factory=dict)  # dirección en bytes → palabra
    simulado: bool = False  # True si salió de FakeTransport y no de la placa

    @classmethod
    def from_bytes(cls, payload: bytes, simulado: bool = False) -> Self:
        """Decodifica el payload. `ErrorLongitud` si el tamaño no coincide con K,
        `ErrorPayload` si el estado o el motivo no existen."""
        if len(payload) < SNAPSHOT_FIJO:
            raise ErrorLongitud(f"snapshot de {len(payload)} B: el mínimo es {SNAPSHOT_FIJO}")
        (k,) = struct.unpack_from("<H", payload, _OFF_K)
        tamano_usada = struct.calcsize(_FMT_USADA)
        if len(payload) != SNAPSHOT_FIJO + tamano_usada * k:
            raise ErrorLongitud(f"snapshot de {len(payload)} B con K = {k}")

        estado_byte, ciclos, pc, riesgos = struct.unpack_from(_FMT_CABECERA, payload, 0)
        try:
            estado = EstadoDU(estado_byte & _NIBBLE)
            motivo = Motivo(estado_byte >> 4)
        except ValueError as error:
            raise ErrorPayload(f"byte de estado inválido: {estado_byte:#04x}") from error

        usadas = struct.iter_unpack(_FMT_USADA, payload[SNAPSHOT_FIJO:])
        return cls(
            estado=estado,
            motivo=None if motivo is Motivo.NINGUNO else motivo,
            ciclos=ciclos,
            pc=pc,
            riesgos=RiesgosCiclo.from_byte(riesgos),
            regs=struct.unpack_from(_FMT_REGS, payload, _OFF_REGS),
            if_id=LatchIFID.from_bytes(payload[_OFF_IF_ID:_OFF_ID_EX]),
            id_ex=LatchIDEX.from_bytes(payload[_OFF_ID_EX:_OFF_EX_MEM]),
            ex_mem=LatchEXMEM.from_bytes(payload[_OFF_EX_MEM:_OFF_MEM_WB]),
            mem_wb=LatchMEMWB.from_bytes(payload[_OFF_MEM_WB:_OFF_K]),
            mem_usada=dict(usadas),
            simulado=simulado,
        )

    def to_bytes(self) -> bytes:
        """Payload en el formato del hardware (inversa de `from_bytes`; `simulado` no viaja)."""
        motivo = self.motivo if self.motivo is not None else Motivo.NINGUNO
        partes = [
            struct.pack(
                _FMT_CABECERA,
                motivo << 4 | self.estado,
                self.ciclos,
                self.pc,
                self.riesgos.to_byte(),
            ),
            struct.pack(_FMT_REGS, *self.regs),
            self.if_id.to_bytes(),
            self.id_ex.to_bytes(),
            self.ex_mem.to_bytes(),
            self.mem_wb.to_bytes(),
            struct.pack("<H", len(self.mem_usada)),
            *(struct.pack(_FMT_USADA, d, v) for d, v in sorted(self.mem_usada.items())),
        ]
        return b"".join(partes)


@dataclass(frozen=True)
class MemRange:
    """Payload de `MEM_DATA`: `n` palabras consecutivas desde `addr` (respuesta de `DUMP_MEM`)."""

    addr: int  # en bytes
    palabras: tuple[int, ...]

    def como_dict(self) -> dict[int, int]:
        """Dirección en bytes → palabra, como `Snapshot.mem_usada`."""
        return {self.addr + 4 * i: p for i, p in enumerate(self.palabras)}

    @classmethod
    def from_bytes(cls, payload: bytes) -> Self:
        """`ErrorLongitud` si el `n` del payload no coincide con la cantidad de palabras."""
        if len(payload) < 4:
            raise ErrorLongitud(f"MEM_DATA de {len(payload)} B: el mínimo es 4")
        addr, n = struct.unpack_from("<HH", payload, 0)
        if len(payload) != 4 + 4 * n:
            raise ErrorLongitud(f"MEM_DATA de {len(payload)} B con n = {n}")
        return cls(addr, struct.unpack_from(f"<{n}I", payload, 4))

    def to_bytes(self) -> bytes:
        n = len(self.palabras)
        return struct.pack(f"<HH{n}I", self.addr, n, *self.palabras)
