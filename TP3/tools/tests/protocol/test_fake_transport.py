"""FakeTransport: la Debug Unit simulada con el modelo del pipeline (US-409, AC4)."""

from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.iss.golden_model import GoldenModel
from riscv_toolkit.iss.golden_model import Motivo as MotivoISS
from riscv_toolkit.protocol.codec import (
    FrameReader,
    Trama,
    encode_cmd,
    encode_dump_mem,
    encode_load,
)
from riscv_toolkit.protocol.comandos import (
    PROTO_VERSION,
    Comando,
    ErrorNack,
    EstadoDU,
    Motivo,
    TipoTrama,
)
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.snapshot import MemRange, Snapshot

SUITE = sorted((Path(__file__).parents[1] / "iss" / "fixtures").glob("*.asm"))
ILEGAL = "addi x1, x0, 7\nsw x1, 8(x0)\n.word 0xFFFFFFFF\n"  # termina con ILLEGAL
PROGRAMA = [0x00500093, 0x00102023, 0x0000000B]  # el de protocolo.md §8
LOOP = "addi x1, x0, 1\nloop: j loop\n"  # no termina nunca

ACK = Trama(TipoTrama.ACK, b"")


def _nack(error: ErrorNack) -> Trama:
    return Trama(TipoTrama.NACK, bytes([error]))


def respuestas(fake: FakeTransport, *comandos: bytes) -> list[Trama]:
    """Manda los comandos y devuelve todas las tramas que respondió."""
    for c in comandos:
        fake.write(c)
    lector, tramas = FrameReader(), []
    while True:
        try:
            tramas.append(lector.leer(fake, timeout=0))
        except TimeoutError:
            return tramas


def snapshot(trama: Trama) -> Snapshot:
    assert trama.tipo is TipoTrama.SNAPSHOT
    return Snapshot.from_bytes(trama.payload, simulado=FakeTransport.simulado)


def cargado(palabras: list[int] = PROGRAMA, **kwargs: int) -> FakeTransport:
    fake = FakeTransport(**kwargs)
    assert respuestas(fake, encode_load(palabras)) == [ACK]
    return fake


# --- AC4: RUN da el mismo estado final que el golden model ---------------------------------
# El PC no se compara: el núcleo lo deja congelado en HALT + 4 (agregado US-306, D3).


@pytest.mark.parametrize("fuente", [*(p.read_text(encoding="utf-8") for p in SUITE), ILEGAL],
                         ids=[*(p.stem for p in SUITE), "ilegal"])  # fmt: skip
def test_run_igual_al_golden_model(fuente: str) -> None:
    palabras = ensamblar(fuente).palabras
    modelo = GoldenModel(palabras)
    modelo.run(10_000)
    esperado = modelo.estado_final()

    ack, final = respuestas(cargado(palabras), encode_cmd(Comando.RUN))
    snap = snapshot(final)

    assert ack == ACK
    assert snap.estado is EstadoDU.HALTED
    assert (
        snap.motivo
        is {MotivoISS.HALTED: Motivo.HALTED, MotivoISS.ILLEGAL: Motivo.ILLEGAL}[esperado.motivo]
    )
    assert snap.regs == esperado.regs
    assert snap.mem_usada == esperado.mem_usada
    assert snap.simulado


def test_hay_programas_en_la_suite() -> None:
    assert len(SUITE) >= 4  # si la ruta estuviera mal, el test de arriba solo probaría ILEGAL


def test_ilegal_reporta_motivo_illegal() -> None:
    _, final = respuestas(cargado(ensamblar(ILEGAL).palabras), encode_cmd(Comando.RUN))
    assert final.payload[0] == 0x26  # motivo ILLEGAL, estado HALTED


# --- R-DU-1: comandos por estado (protocolo §4.1) ------------------------------------------


def test_al_encender_esta_en_idle() -> None:
    fake = FakeTransport()
    assert respuestas(fake, encode_cmd(Comando.STEP), encode_cmd(Comando.RUN),
                      encode_cmd(Comando.ABORT)) == [_nack(ErrorNack.ESTADO)] * 3  # fmt: skip
    (dump,) = respuestas(fake, encode_cmd(Comando.DUMP))
    assert snapshot(dump).estado is EstadoDU.IDLE
    assert respuestas(fake, encode_cmd(Comando.RESET)) == [ACK]  # sin programa: sigue en IDLE
    assert respuestas(fake, encode_cmd(Comando.STEP)) == [_nack(ErrorNack.ESTADO)]


def test_ping_y_desconocido() -> None:
    fake = FakeTransport()
    assert respuestas(fake, encode_cmd(Comando.PING), b"Z") == [
        Trama(TipoTrama.PING_INFO, bytes([PROTO_VERSION])),
        _nack(ErrorNack.DESCONOCIDO),
    ]


def test_step_a_step_hasta_el_halt() -> None:
    fake = cargado()
    # Un STEP es un ciclo: addi, sw y halt tardan 3 + 4 = 7 (el halt sale de WB en el 7).
    (s1,) = respuestas(fake, encode_cmd(Comando.STEP))
    snap = snapshot(s1)
    assert snap.estado is EstadoDU.STEPPING
    assert (snap.ciclos, snap.pc, snap.regs[1]) == (1, 4, 0)  # addi recién buscada
    assert (snap.if_id.instr, snap.if_id.valid) == (PROGRAMA[0], True)
    assert not snap.id_ex.valid

    (s2,) = respuestas(fake, encode_cmd(Comando.STEP))
    assert snapshot(s2).id_ex.instr == PROGRAMA[0]  # addi avanzó a EX
    assert snapshot(s2).id_ex.reg_write  # con sus señales de control
    assert snapshot(s2).riesgos.fwd_b == 0  # sw todavía en ID

    (s3,) = respuestas(fake, encode_cmd(Comando.STEP))
    assert snapshot(s3).riesgos.fwd_b == 0b10  # sw en EX: x1 desde EX/MEM (store_data)

    for _ in range(4):
        (ultimo,) = respuestas(fake, encode_cmd(Comando.STEP))
    fin = snapshot(ultimo)
    assert fin.ciclos == 7
    assert (fin.regs[1], fin.mem_usada) == (5, {0: 5})
    assert (fin.estado, fin.motivo) == (EstadoDU.HALTED, Motivo.HALTED)
    assert not fin.if_id.valid  # pipeline vacío
    assert not fin.id_ex.valid

    assert respuestas(fake, encode_cmd(Comando.STEP)) == [_nack(ErrorNack.ESTADO)]
    (dump,) = respuestas(fake, encode_cmd(Comando.DUMP))
    assert snapshot(dump).motivo is Motivo.HALTED  # el motivo se conserva

    assert respuestas(fake, encode_cmd(Comando.RESET)) == [ACK]
    (dump,) = respuestas(fake, encode_cmd(Comando.DUMP))
    limpio = snapshot(dump)
    assert (limpio.estado, limpio.motivo, limpio.regs[1], limpio.mem_usada) == (
        EstadoDU.READY, None, 0, {},
    )  # fmt: skip


def test_run_que_no_termina_y_abort() -> None:
    fake = cargado(ensamblar(LOOP).palabras, max_ciclos=500)
    assert respuestas(fake, encode_cmd(Comando.RUN)) == [ACK]  # sin snapshot: sigue en RUN
    assert respuestas(fake, encode_cmd(Comando.PING))[0].tipo is TipoTrama.PING_INFO
    for cmd in (Comando.DUMP, Comando.STEP, Comando.RESET, Comando.LOAD, Comando.DUMP_MEM):
        assert respuestas(fake, bytes([cmd])) == [_nack(ErrorNack.ESTADO)]

    (final,) = respuestas(fake, encode_cmd(Comando.ABORT))
    assert final.payload[0] == 0x36  # motivo ABORTED, estado HALTED
    snap = snapshot(final)
    assert (snap.ciclos, snap.regs[1]) == (500 + 2, 1)  # 2 ciclos de drenado (stop_fetch)
    assert not any(x.valid for x in (snap.if_id, snap.id_ex, snap.ex_mem, snap.mem_wb))


# --- LOAD ----------------------------------------------------------------------------------


def test_load_en_pedazos() -> None:
    fake = FakeTransport()
    trama = encode_load(PROGRAMA)
    for i in range(len(trama) - 1):
        assert respuestas(fake, trama[i : i + 1]) == []  # espera los bytes que faltan
    assert respuestas(fake, trama[-1:]) == [ACK]


def test_load_con_checksum_malo_deja_idle() -> None:
    fake = cargado()
    trama = bytearray(encode_load(PROGRAMA))
    trama[-1] ^= 0xFF
    assert respuestas(fake, bytes(trama)) == [_nack(ErrorNack.CHECKSUM)]
    assert respuestas(fake, encode_cmd(Comando.STEP)) == [_nack(ErrorNack.ESTADO)]


def test_load_con_n_cero_drena_y_responde_tamano() -> None:
    fake = cargado()
    assert respuestas(fake, bytes.fromhex("4C 0000 93005000 FF")) == [_nack(ErrorNack.TAMANO)]
    assert respuestas(fake, encode_cmd(Comando.STEP)) == [_nack(ErrorNack.ESTADO)]


def test_load_limpia_lo_anterior() -> None:
    fake = cargado()
    respuestas(fake, encode_cmd(Comando.RUN))
    assert respuestas(fake, encode_load(PROGRAMA)) == [ACK]
    (dump,) = respuestas(fake, encode_cmd(Comando.DUMP))
    assert (snapshot(dump).estado, snapshot(dump).mem_usada) == (EstadoDU.READY, {})


# --- DUMP_MEM ------------------------------------------------------------------------------


def test_dump_mem_del_ejemplo() -> None:  # §8.9
    fake = cargado()
    respuestas(fake, encode_cmd(Comando.RUN))
    (datos,) = respuestas(fake, encode_dump_mem(0x000, 2))
    assert datos.tipo is TipoTrama.MEM_DATA
    assert MemRange.from_bytes(datos.payload) == MemRange(0, (5, 0))


@pytest.mark.parametrize(("addr", "n"), [(0x3FC, 2), (0x002, 1), (0x000, 0), (0x400, 1)])
def test_dump_mem_fuera_de_rango(addr: int, n: int) -> None:
    fake = cargado()
    assert respuestas(fake, encode_dump_mem(addr, n)) == [_nack(ErrorNack.RANGO)]
    (dump,) = respuestas(fake, encode_cmd(Comando.DUMP))
    assert snapshot(dump).estado is EstadoDU.READY  # sin cambio de estado


def test_close_descarta_lo_pendiente() -> None:
    fake = cargado()
    fake.write(encode_cmd(Comando.PING))
    fake.close()
    assert fake.read(10, timeout=0) == b""


def test_dump_mem_en_pedazos() -> None:
    fake = cargado()
    trama = encode_dump_mem(0x000, 1)
    assert respuestas(fake, trama[:3]) == []
    (datos,) = respuestas(fake, trama[3:])
    assert MemRange.from_bytes(datos.payload) == MemRange(0, (0,))


def test_latches_con_las_cuatro_anteriores() -> None:
    palabras = ensamblar(
        "addi x1, x0, 1\naddi x2, x0, 2\naddi x3, x0, 3\naddi x4, x0, 4\naddi x5, x0, 5\n"
    ).palabras
    fake = cargado(palabras)
    *_, ultimo = respuestas(fake, *[encode_cmd(Comando.STEP)] * 4)
    snap = snapshot(ultimo)
    assert snap.pc == 16  # IF: la próxima, la quinta
    latches = [snap.if_id.instr, snap.id_ex.instr, snap.ex_mem.instr, snap.mem_wb.instr]
    assert latches == palabras[3::-1]
    assert snap.mem_wb.pc_plus4 == 4  # la primera, en 0x000
