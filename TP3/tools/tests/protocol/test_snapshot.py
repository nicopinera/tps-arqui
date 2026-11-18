"""Snapshot y MemRange: payloads con nombre (US-409, AC1 y AC2, ADR-017)."""

from pathlib import Path

import pytest

from riscv_toolkit.protocol.codec import ErrorLongitud, ErrorPayload, FrameReader, encode_trama
from riscv_toolkit.protocol.comandos import EstadoDU, Motivo, TipoTrama
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    MemRange,
    RiesgosCiclo,
    Snapshot,
)

CAPTURA = Path(__file__).parent / "fixtures" / "snapshot_sim.bin"

# §8.5: STEP desde READY. IF/ID tiene el addi; el resto, burbujas.
TRAMA_STEP = bytes.fromhex(
    "A5 03 DD 00"
    "04" "01000000" "04000000" "00"
    + "00" * 128
    + "00000000 04000000 93005000 01"
    + "00" * (31 + 19 + 18)
    + "0000"
    "19"
)  # fmt: skip

# §8.7: snapshot final de RUN, x1 = 5 y [0x000] = 5.
TRAMA_RUN = bytes.fromhex(
    "A5 03 E3 00"
    "16" "07000000" "0C000000" "00"
    "00000000 05000000" + "00" * 120
    + "00" * 81
    + "0100" "0000 05000000"
    "FC"
)  # fmt: skip


def _payload(trama: bytes) -> bytes:
    lector = FrameReader()
    lector.feed(trama)
    leida = lector.pop()  # además valida el checksum del ejemplo
    assert leida is not None
    assert leida.tipo is TipoTrama.SNAPSHOT
    return leida.payload


# --- Ejemplos del protocolo (AC1) ----------------------------------------------------------


def test_snapshot_de_step() -> None:
    snap = Snapshot.from_bytes(_payload(TRAMA_STEP))
    assert snap.estado is EstadoDU.STEPPING
    assert snap.motivo is None
    assert (snap.ciclos, snap.pc) == (1, 4)
    assert snap.riesgos == RiesgosCiclo()
    assert snap.regs == (0,) * 32
    assert snap.if_id == LatchIFID(pc=0, pc_plus4=4, instr=0x00500093, valid=True)
    assert (snap.id_ex, snap.ex_mem, snap.mem_wb) == (LatchIDEX(), LatchEXMEM(), LatchMEMWB())
    assert snap.mem_usada == {}
    assert not snap.simulado


def test_snapshot_final_de_run() -> None:
    snap = Snapshot.from_bytes(_payload(TRAMA_RUN))
    assert (snap.estado, snap.motivo) == (EstadoDU.HALTED, Motivo.HALTED)
    assert (snap.ciclos, snap.pc) == (7, 0x0C)
    assert snap.regs[1] == 5
    assert snap.mem_usada == {0x000: 5}


@pytest.mark.parametrize("trama", [TRAMA_STEP, TRAMA_RUN])
def test_ida_y_vuelta_de_los_ejemplos(trama: bytes) -> None:
    payload = _payload(trama)
    assert encode_trama(TipoTrama.SNAPSHOT, Snapshot.from_bytes(payload).to_bytes()) == trama


# --- Captura de la simulación (AC2) --------------------------------------------------------


def test_captura_de_la_simulacion() -> None:
    """Snapshot real de tb_du_cmd_fsm (RUN que termina en ILLEGAL) con el core_stub.

    El stub arma todo desde su contador c: x_i = {i, c}, PC = 4c, cada latch con su etiqueta
    (22/33/44) y `instr` = {EE, c}, y un store cada 4 ciclos en la palabra c[9:2] con {D0, c}.
    """
    payload = CAPTURA.read_bytes()
    snap = Snapshot.from_bytes(payload)
    c = snap.regs[1] & 0xFFFFFF

    assert (snap.estado, snap.motivo) == (EstadoDU.HALTED, Motivo.ILLEGAL)
    assert snap.regs == (0, *((i << 24) | c for i in range(1, 32)))
    assert snap.pc == 4 * c
    assert snap.riesgos == RiesgosCiclo(
        stall=bool(c & 1),
        flush_if_id=bool(c >> 1 & 1),
        flush_id_ex=bool(c >> 2 & 1),
        fwd_a=c >> 3 & 3,
        fwd_b=c >> 5 & 3,
    )
    assert snap.if_id == LatchIFID(pc=4 * c, pc_plus4=4 * c + 4, instr=0x0000000B, valid=True)
    traza = 0xEE << 24 | c
    assert snap.id_ex == LatchIDEX(pc=0x22 << 24 | c, valid=True, instr=traza)
    assert snap.ex_mem == LatchEXMEM(alu_result=0x33 << 24 | c, valid=True, instr=traza)
    assert snap.mem_wb == LatchMEMWB(alu_result=0x44 << 24 | c, valid=True, instr=traza)

    assert list(snap.mem_usada) == list(range(0, 1024, 4))  # K = 256, dirección creciente
    for direccion, dato in snap.mem_usada.items():
        assert dato >> 24 == 0xD0
        assert dato & 0x3FF == direccion  # c[9:0] del store = 4·palabra

    assert snap.to_bytes() == payload


# --- Flags bit a bit -----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("byte", "riesgos"),
    [
        (0x01, RiesgosCiclo(stall=True)),
        (0x02, RiesgosCiclo(flush_if_id=True)),
        (0x04, RiesgosCiclo(flush_id_ex=True)),
        (0x10, RiesgosCiclo(fwd_a=2)),  # EX/MEM
        (0x20, RiesgosCiclo(fwd_b=1)),  # MEM/WB
    ],
)
def test_byte_de_riesgos(byte: int, riesgos: RiesgosCiclo) -> None:
    assert RiesgosCiclo.from_byte(byte) == riesgos
    assert riesgos.to_byte() == byte


def test_flags_de_los_latches_en_su_bit() -> None:
    # Un flag por vez: cada uno tiene que caer en el bit de la §6.2 y volver igual.
    id_ex = LatchIDEX(jalr=True, result_src=2, halt=True)
    datos = id_ex.to_bytes()
    assert (datos[25], datos[26]) == (0x80, 0x11)  # jalr = b7 de flags 1; halt b0, rs = b4-3
    assert LatchIDEX.from_bytes(datos) == id_ex

    ex_mem = LatchEXMEM(mem_write=True, result_src=3)
    assert ex_mem.to_bytes()[14] == 0xE0
    assert LatchEXMEM.from_bytes(ex_mem.to_bytes()) == ex_mem

    mem_wb = LatchMEMWB(illegal=True, result_src=1)
    assert mem_wb.to_bytes()[13] == 0x14
    assert LatchMEMWB.from_bytes(mem_wb.to_bytes()) == mem_wb


def test_tamanos_de_los_latches() -> None:
    assert [len(x.to_bytes()) for x in (LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB())] == [
        13, 31, 19, 18,
    ]  # fmt: skip


# --- Errores -------------------------------------------------------------------------------


def test_snapshot_con_k_que_no_coincide() -> None:
    payload = bytearray(_payload(TRAMA_STEP))
    payload[219] = 1  # dice K = 1 pero no trae la palabra
    with pytest.raises(ErrorLongitud):
        Snapshot.from_bytes(bytes(payload))


def test_snapshot_corto() -> None:
    with pytest.raises(ErrorLongitud):
        Snapshot.from_bytes(bytes(100))


@pytest.mark.parametrize("estado", [0x07, 0x46])  # estado DU 7 y motivo 4 no existen
def test_snapshot_con_estado_invalido(estado: int) -> None:
    payload = bytearray(221)
    payload[0] = estado
    with pytest.raises(ErrorPayload):
        Snapshot.from_bytes(bytes(payload))


def test_simulado_lo_decide_quien_decodifica() -> None:
    assert Snapshot.from_bytes(_payload(TRAMA_STEP), simulado=True).simulado


# --- MemRange (DUMP_MEM) -------------------------------------------------------------------


def test_mem_range_del_ejemplo() -> None:  # §8.9
    rango = MemRange.from_bytes(bytes.fromhex("0000 0200 05000000 00000000"))
    assert rango == MemRange(addr=0, palabras=(5, 0))
    assert rango.como_dict() == {0x000: 5, 0x004: 0}
    assert rango.to_bytes().hex() == "0000020005000000" + "00000000"


@pytest.mark.parametrize("payload", ["0000 0200 05000000", "0000", "0000 0100"])
def test_mem_range_con_n_que_no_coincide(payload: str) -> None:
    with pytest.raises(ErrorLongitud):
        MemRange.from_bytes(bytes.fromhex(payload))
