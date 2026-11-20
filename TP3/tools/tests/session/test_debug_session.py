"""DebugSession con FakeTransport y con transportes que inyectan errores (US-410)."""

import threading
import time
from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.iss.golden_model import GoldenModel
from riscv_toolkit.protocol.codec import (
    ErrorChecksum,
    ErrorPayload,
    ErrorTramaTruncada,
    encode_trama,
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
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    RiesgosCiclo,
    Snapshot,
)
from riscv_toolkit.session.debug_session import (
    DebugSession,
    ErrorNackDU,
    ErrorRespuesta,
    ErrorVersion,
    Timeouts,
    mensaje_nack,
)

ASM = Path(__file__).parents[3] / "asm"
FIXTURES_ASM = Path(__file__).parents[1] / "fixtures" / "asm"
FIBONACCI = ensamblar((FIXTURES_ASM / "fibonacci.asm").read_text(encoding="utf-8")).palabras
LOOP = ensamblar("addi x1, x0, 1\nloop: j loop\n").palabras
RAPIDO = Timeouts(respuesta=0.05, snapshot=0.05, sondeo=0.01)

ACK = encode_trama(TipoTrama.ACK, b"")
PING_INFO = encode_trama(TipoTrama.PING_INFO, bytes([PROTO_VERSION]))


def nack(codigo: int) -> bytes:
    return encode_trama(TipoTrama.NACK, bytes([codigo]))


def trama_snapshot(estado: EstadoDU, motivo: Motivo | None) -> bytes:
    snap = Snapshot(estado, motivo, 7, 0, RiesgosCiclo(), (0,) * 32,
                    LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB())  # fmt: skip
    return encode_trama(TipoTrama.SNAPSHOT, snap.to_bytes())


class Guionado:
    """Responde cada `write` con el próximo elemento del guion (bytes crudos, o b"" = nada)."""

    simulado = False

    def __init__(self, *guion: bytes) -> None:
        self.guion = list(guion)
        self.escrito: list[bytes] = []
        self.cerrado = False
        self._salida = bytearray()

    def write(self, datos: bytes) -> None:
        self.escrito.append(datos)
        if self.guion:
            self._salida += self.guion.pop(0)

    def read(self, n: int, timeout: float | None) -> bytes:
        datos = bytes(self._salida[:n])
        del self._salida[:n]
        return datos

    def close(self) -> None:
        self.cerrado = True


class CtrlC(FakeTransport):
    """El fake, pero la primera vez que no hay nada para leer simula un Ctrl+C."""

    def __init__(self) -> None:
        super().__init__(max_ciclos=50)
        self.armado = True

    def read(self, n: int, timeout: float | None) -> bytes:
        datos = super().read(n, 0)
        if not datos and self.armado:
            self.armado = False
            raise KeyboardInterrupt
        return datos


def sesion_fake(**kwargs: int) -> DebugSession:
    return DebugSession(FakeTransport(**kwargs), RAPIDO)


# --- Casos de uso con FakeTransport --------------------------------------------------------


def test_load_y_run_igual_al_golden_model() -> None:
    modelo = GoldenModel(FIBONACCI)
    modelo.run(10_000)
    esperado = modelo.estado_final()
    sesion = sesion_fake()

    sesion.load(FIBONACCI)
    snap = sesion.run()

    assert snap.estado is EstadoDU.HALTED
    assert snap.motivo is Motivo.HALTED
    assert snap.regs == esperado.regs
    assert snap.mem_usada == esperado.mem_usada
    assert snap.simulado
    assert sesion.estado is EstadoDU.HALTED
    assert sesion.historial.actual == snap


def test_conectar_y_ping() -> None:
    sesion = sesion_fake()
    assert sesion.conectar() == PROTO_VERSION
    assert sesion.ping() == PROTO_VERSION


def test_step_llena_el_historial_y_load_lo_limpia() -> None:
    sesion = sesion_fake()
    sesion.load(FIBONACCI)
    primero, segundo = sesion.step(), sesion.step()

    assert (primero.ciclos, segundo.ciclos) == (1, 2)
    assert sesion.estado is EstadoDU.STEPPING
    assert len(sesion.historial) == 2
    sesion.load(FIBONACCI)
    assert len(sesion.historial) == 0


def test_reset_vuelve_al_principio() -> None:
    sesion = sesion_fake()
    sesion.load(FIBONACCI)
    sesion.step()
    sesion.reset()
    assert sesion.estado is EstadoDU.READY
    assert sesion.step().ciclos == 1


def test_reset_sin_programa_queda_en_idle() -> None:
    sesion = sesion_fake()
    sesion.dump()  # aprende que está en IDLE
    sesion.reset()
    assert sesion.estado is EstadoDU.IDLE


def test_dump_y_dump_mem() -> None:
    sesion = sesion_fake()
    sesion.load(FIBONACCI)
    sesion.run()
    assert sesion.dump().motivo is Motivo.HALTED  # el motivo se conserva (§5)
    rango = sesion.dump_mem(0x8, 3)
    assert rango.como_dict() == {0x8: 1, 0xC: 2, 0x10: 3}


def test_context_manager_cierra_el_transporte() -> None:
    transporte = Guionado()
    with DebugSession(transporte):
        assert not transporte.cerrado
    assert transporte.cerrado


# --- NACK → ErrorNackDU con mensaje legible (AC2) -------------------------------------------


def test_step_despues_de_halt_explica_el_estado() -> None:
    sesion = sesion_fake()
    sesion.load(FIBONACCI)
    sesion.run()
    with pytest.raises(ErrorNackDU) as error:
        sesion.step()
    assert error.value.codigo is ErrorNack.ESTADO
    assert error.value.estado is EstadoDU.HALTED
    assert str(error.value) == (
        "No se puede ejecutar STEP: el procesador está detenido (HALTED). "
        "Cargá o reseteá el programa."
    )
    assert len(sesion.historial) == 1  # el DUMP para averiguar el estado no se guarda


def test_run_sin_programa() -> None:
    with pytest.raises(ErrorNackDU, match="no hay un programa cargado"):
        sesion_fake().run()


def test_abort_sin_ejecucion() -> None:
    with pytest.raises(ErrorNackDU, match="no hay una ejecución en curso"):
        sesion_fake().abort()


def test_dump_mem_fuera_de_rango() -> None:
    with pytest.raises(ErrorNackDU, match="DUMP_MEM falló: la dirección no está alineada") as e:
        sesion_fake().dump_mem(0x3FC, 2)
    assert e.value.codigo is ErrorNack.RANGO


def test_load_durante_run_no_manda_la_trama() -> None:
    sesion = DebugSession(CtrlC(), RAPIDO)
    sesion.load(LOOP)
    with pytest.raises(KeyboardInterrupt):
        sesion.run()
    with pytest.raises(ErrorNackDU, match=r"corriendo \(RUN\)") as error:
        sesion.load(FIBONACCI)  # sus palabras se tomarían como comandos sueltos
    assert error.value.estado is EstadoDU.RUN
    assert sesion.abort().motivo is Motivo.ABORTED  # la DU no recibió nada raro


def test_dump_mem_con_estado_desconocido_pregunta_antes() -> None:
    fake = FakeTransport(max_ciclos=10)
    otra = DebugSession(fake, RAPIDO)  # otro proceso dejó la placa corriendo
    otra.load(LOOP)
    fake.write(bytes([Comando.RUN]))
    fake.read(100, 0)  # su ACK, que leyó el otro proceso

    sesion = DebugSession(fake, RAPIDO)
    with pytest.raises(ErrorNackDU, match=r"corriendo \(RUN\)"):
        sesion.dump_mem(0, 4)
    assert fake.read(100, 0) == b""  # solo se mandó el DUMP de la consulta (y su NACK se leyó)


def test_reset_rechazado_en_run_no_pregunta() -> None:
    transporte = Guionado(nack(ErrorNack.ESTADO))
    with pytest.raises(ErrorNackDU, match=r"corriendo \(RUN\)"):
        DebugSession(transporte, RAPIDO).reset()
    assert transporte.escrito == [bytes([Comando.RESET])]


def test_load_fallido_deja_idle() -> None:
    listo = trama_snapshot(EstadoDU.READY, None)  # respuesta al DUMP que pregunta el estado
    sesion = DebugSession(Guionado(listo, nack(ErrorNack.CHECKSUM)), RAPIDO)
    with pytest.raises(ErrorNackDU, match="La IMEM quedó vacía"):
        sesion.load([0x13])
    assert sesion.estado is EstadoDU.IDLE


def test_estado_desconocido_si_la_placa_no_contesta_el_dump() -> None:
    sesion = DebugSession(Guionado(nack(ErrorNack.ESTADO), b""), RAPIDO)
    with pytest.raises(ErrorNackDU, match="no lo acepta en su estado actual"):
        sesion.step()


@pytest.mark.parametrize("codigo", [c for c in ErrorNack if c is not ErrorNack.ESTADO])
def test_todos_los_codigos_tienen_mensaje(codigo: ErrorNack) -> None:
    assert mensaje_nack(Comando.LOAD, codigo, None).startswith("LOAD falló: ")


# --- RUN: espera, Ctrl+C y ABORT (AC5) -----------------------------------------------------


def test_ctrl_c_durante_run_y_abort() -> None:
    sesion = DebugSession(CtrlC(), RAPIDO)
    sesion.load(LOOP)
    with pytest.raises(KeyboardInterrupt):
        sesion.run()
    assert sesion.estado is EstadoDU.RUN

    snap = sesion.abort()
    assert snap.motivo is Motivo.ABORTED
    assert snap.regs[1] == 1
    assert snap.estado is EstadoDU.HALTED


def test_run_con_bandera_levantada_aborta() -> None:
    sesion = DebugSession(FakeTransport(max_ciclos=10), RAPIDO)
    sesion.load(LOOP)
    cancelar = threading.Event()
    cancelar.set()

    snap = sesion.run(cancelar)
    assert snap.motivo is Motivo.ABORTED
    assert snap.estado is EstadoDU.HALTED
    assert sesion.estado is EstadoDU.HALTED


def test_run_cancelado_desde_otro_hilo() -> None:
    # Lo que hace la GUI: el worker espera en run() y el botón Abortar levanta la bandera.
    sesion = DebugSession(FakeTransport(max_ciclos=10), RAPIDO)
    sesion.load(LOOP)
    cancelar = threading.Event()
    threading.Timer(0.1, cancelar.set).start()

    inicio = time.monotonic()
    assert sesion.run(cancelar).motivo is Motivo.ABORTED
    assert time.monotonic() - inicio < 1


def test_run_que_termina_ignora_la_bandera() -> None:
    sesion = DebugSession(FakeTransport(), RAPIDO)
    sesion.load(FIBONACCI)
    assert sesion.run(threading.Event()).motivo is Motivo.HALTED


def test_run_con_limite_corta_con_timeout() -> None:
    sesion = DebugSession(FakeTransport(max_ciclos=10), Timeouts(run=0.05, sondeo=0.01))
    sesion.load(LOOP)
    with pytest.raises(TimeoutError, match="RUN no terminó"):
        sesion.run()


def test_run_ignora_nack_de_paridad() -> None:
    final = trama_snapshot(EstadoDU.HALTED, Motivo.HALTED)
    sesion = DebugSession(Guionado(ACK + nack(ErrorNack.PARIDAD) + final), RAPIDO)
    assert sesion.run().motivo is Motivo.HALTED


def test_run_con_otro_nack_falla() -> None:
    sesion = DebugSession(Guionado(ACK + nack(ErrorNack.DESCONOCIDO)), RAPIDO)
    with pytest.raises(ErrorNackDU):
        sesion.run()


def test_abort_justo_cuando_termino_descarta_el_nack() -> None:
    final = trama_snapshot(EstadoDU.HALTED, Motivo.HALTED)
    transporte = Guionado(final + nack(ErrorNack.ESTADO), PING_INFO)
    sesion = DebugSession(transporte, RAPIDO)

    assert sesion.abort().motivo is Motivo.HALTED
    assert sesion.ping() == PROTO_VERSION  # el NACK viejo no quedó como respuesta del PING


# --- Placa que no responde o responde mal (AC3) --------------------------------------------


def test_placa_muda_termina_con_timeout() -> None:
    sesion = DebugSession(Guionado(), RAPIDO)
    inicio = time.monotonic()
    with pytest.raises(TimeoutError, match="no respondió a 3 PING"):
        sesion.conectar()
    assert time.monotonic() - inicio < 1


def test_conectar_reintenta_el_ping() -> None:
    transporte = Guionado(b"", b"\xa5\x99\x00\x00", PING_INFO)  # nada, basura, respuesta
    assert DebugSession(transporte, RAPIDO).conectar() == PROTO_VERSION
    assert len(transporte.escrito) == 3


def test_conectar_con_otra_version() -> None:
    otra = encode_trama(TipoTrama.PING_INFO, bytes([PROTO_VERSION + 1]))
    with pytest.raises(ErrorVersion, match="mismo commit"):
        DebugSession(Guionado(otra), RAPIDO).conectar()


def test_respuesta_de_otro_tipo() -> None:
    with pytest.raises(ErrorRespuesta, match="se esperaba SNAPSHOT y llegó ACK"):
        DebugSession(Guionado(ACK), RAPIDO).step()


def test_nack_con_codigo_inexistente() -> None:
    with pytest.raises(ErrorPayload):
        DebugSession(Guionado(nack(0)), RAPIDO).reset()


def test_snapshot_corrupto_y_despues_sigue() -> None:
    corrupta = bytearray(trama_snapshot(EstadoDU.READY, None))
    corrupta[-1] ^= 0xFF
    sesion = DebugSession(Guionado(bytes(corrupta), PING_INFO), RAPIDO)
    with pytest.raises(ErrorChecksum):
        sesion.dump()
    assert sesion.ping() == PROTO_VERSION  # resincronizó


def test_snapshot_cortado() -> None:
    cortada = trama_snapshot(EstadoDU.READY, None)[:100]
    with pytest.raises(ErrorTramaTruncada):
        DebugSession(Guionado(cortada), RAPIDO).dump()
