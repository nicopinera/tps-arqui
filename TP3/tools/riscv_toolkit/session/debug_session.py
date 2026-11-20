"""Sesión de depuración: los casos de uso de la Debug Unit como métodos (US-410).

Es la única capa por la que la CLI, la GUI y `verify_board.py` hablan con la placa. Cada método
manda un comando, espera la respuesta que le corresponde (`LOAD` → `ACK`, `STEP` → `SNAPSHOT`,
…) y la devuelve como objeto, o lanza una excepción con un mensaje legible:

- `ErrorNackDU`: la Debug Unit respondió `NACK` (lleva el código y el comando);
- `ErrorRespuesta`: llegó una trama válida pero de otro tipo (la sesión quedó desincronizada);
- `TimeoutError`: la placa no respondió a tiempo (protocolo §7.4);
- `ErrorTrama` (del codec): llegó basura; ya se descartó.

Debajo, el `Transport` decide si es la placa real o `FakeTransport`.
"""

import time
from collections.abc import Sequence
from contextlib import suppress
from dataclasses import dataclass
from types import TracebackType
from typing import Self

from riscv_toolkit.protocol.codec import (
    ErrorPayload,
    ErrorTrama,
    FrameReader,
    Trama,
    encode_cmd,
    encode_dump_mem,
    encode_load,
)
from riscv_toolkit.protocol.comandos import (
    DMEM_DEPTH,
    IMEM_DEPTH,
    PROTO_VERSION,
    RX_TIMEOUT_MS,
    Comando,
    ErrorNack,
    EstadoDU,
    Motivo,
    TipoTrama,
)
from riscv_toolkit.protocol.snapshot import MemRange, Snapshot
from riscv_toolkit.protocol.transport import Transport
from riscv_toolkit.session.history import SnapshotHistory


@dataclass(frozen=True)
class Timeouts:
    """Segundos de espera por cada tipo de respuesta (protocolo §7.4)."""

    respuesta: float = 1.0  # ACK / NACK, PING_INFO, MEM_DATA
    snapshot: float = 2.0  # STEP, DUMP, ABORT: el snapshot más grande tarda ~1 s (ADR-008)
    run: float | None = None  # snapshot final de RUN: sin límite (ADR-010), se corta con ABORT
    sondeo: float = 0.2  # cada cuánto RUN vuelve a leer mientras espera (deja pasar el Ctrl+C)


# --- Errores -------------------------------------------------------------------------------


class ErrorSesion(Exception):  # noqa: N818
    """Base de los errores propios de la sesión."""


class ErrorNackDU(ErrorSesion):
    """La Debug Unit respondió `NACK`. El mensaje explica qué pasó y qué hacer (AC2)."""

    def __init__(self, comando: Comando, codigo: ErrorNack, estado: EstadoDU | None) -> None:
        self.comando = comando
        self.codigo = codigo
        self.estado = estado  # el de la DU cuando rechazó el comando, si se pudo averiguar
        super().__init__(mensaje_nack(comando, codigo, estado))


class ErrorRespuesta(ErrorSesion):
    """Llegó una trama válida pero no la que corresponde al comando."""


class ErrorVersion(ErrorSesion):
    """La placa habla otra versión del protocolo: bitstream y toolkit de commits distintos."""


_POR_QUE_ESTADO = {
    EstadoDU.IDLE: "no hay un programa cargado. Cargá uno con load.",
    EstadoDU.RUN: "el procesador está corriendo (RUN). Esperá a que termine o mandá abort.",
    EstadoDU.HALTED: "el procesador está detenido (HALTED). Cargá o reseteá el programa.",
}

_POR_QUE_ERROR = {
    ErrorNack.DESCONOCIDO: "la Debug Unit no reconoce el comando (¿bitstream de otra versión?).",
    ErrorNack.CHECKSUM: "el programa llegó corrupto (checksum inválido). "
    "La IMEM quedó vacía: volvé a cargarlo.",
    ErrorNack.TAMANO: f"el programa tiene que tener entre 1 y {IMEM_DEPTH} palabras. "
    "La IMEM quedó vacía.",
    ErrorNack.RANGO: "la dirección no está alineada a 4 o el rango se pasa de la DMEM "
    f"({DMEM_DEPTH * 4} bytes).",
    ErrorNack.TIMEOUT: f"los argumentos llegaron incompletos ({RX_TIMEOUT_MS} ms sin bytes). "
    "Si era un LOAD, la IMEM quedó vacía.",
    ErrorNack.PARIDAD: "un byte llegó con error de paridad (¿ruido o baud rate distinto?). "
    "Si era un LOAD, la IMEM quedó vacía.",
}


def mensaje_nack(comando: Comando, codigo: ErrorNack, estado: EstadoDU | None) -> str:
    """Texto para el usuario de un `NACK` (AC2)."""
    if codigo is not ErrorNack.ESTADO:
        return f"{comando.name} falló: {_POR_QUE_ERROR[codigo]}"
    if comando is Comando.ABORT and estado is not EstadoDU.RUN:
        por_que = "no hay una ejecución en curso para abortar."
    elif estado in _POR_QUE_ESTADO:
        por_que = _POR_QUE_ESTADO[estado]
    else:  # no se pudo averiguar el estado (la placa dejó de responder)
        por_que = "la Debug Unit no lo acepta en su estado actual."
    return f"No se puede ejecutar {comando.name}: {por_que}"


# Comandos que la DU solo rechaza en RUN (protocolo §4.1): su NACK(ESTADO) ya dice el estado.
_RECHAZADOS_SOLO_EN_RUN = {Comando.LOAD, Comando.RESET, Comando.DUMP, Comando.DUMP_MEM}


# --- Sesión --------------------------------------------------------------------------------


class DebugSession:
    """Una conversación con la Debug Unit a través de `transport`.

    `estado` es el último estado conocido de la DU (None hasta el primer snapshot) e `historial`
    guarda los snapshots que llegaron desde el último LOAD o RESET.
    """

    def __init__(self, transport: Transport, timeouts: Timeouts | None = None) -> None:
        self.transport = transport
        self.timeouts = timeouts if timeouts is not None else Timeouts()
        self.historial = SnapshotHistory()
        self.estado: EstadoDU | None = None
        self._lector = FrameReader()

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        tipo: type[BaseException] | None,
        error: BaseException | None,
        traza: TracebackType | None,
    ) -> None:
        self.close()

    def close(self) -> None:
        self.transport.close()

    # --- Casos de uso ----------------------------------------------------------------------

    def conectar(self, intentos: int = 3) -> int:
        """`PING` hasta que responda y verifica la versión del protocolo. Devuelve la versión.

        Se reintenta porque recién abierto el puerto (o recién programada la placa) puede haber
        basura en la línea o perderse el primer byte. Los demás comandos **no** se reintentan:
        repetir un `STEP` avanzaría dos ciclos.
        """
        for _ in range(intentos):
            try:
                version = self.ping()
            except (TimeoutError, ErrorTrama) as error:
                ultimo = error
                continue
            if version != PROTO_VERSION:
                raise ErrorVersion(
                    f"la placa habla el protocolo v{version} y el toolkit el v{PROTO_VERSION}: "
                    "programá el bitstream del mismo commit"
                )
            return version
        raise TimeoutError(f"la Debug Unit no respondió a {intentos} PING") from ultimo

    def ping(self) -> int:
        """Versión del protocolo que habla la placa. Vale en cualquier estado."""
        trama = self._pedir(Comando.PING, TipoTrama.PING_INFO, self.timeouts.respuesta)
        return trama.payload[0]

    def load(self, palabras: Sequence[int]) -> None:
        """Carga el programa (`imagen.palabras`) en la IMEM. Queda en READY, todo limpio."""
        self._rechazar_si_corre(Comando.LOAD)
        try:
            self._pedir(Comando.LOAD, TipoTrama.ACK, self.timeouts.respuesta, encode_load(palabras))
        except ErrorNackDU as error:
            if error.codigo is not ErrorNack.ESTADO:
                self.estado = EstadoDU.IDLE  # un LOAD fallido deja la IMEM con HALT (§7.1)
            raise
        self.estado = EstadoDU.READY
        self.historial.limpiar()

    def reset(self) -> None:
        """Vuelve al inicio del programa cargado (todo limpio menos la IMEM, ADR-009)."""
        self._pedir(Comando.RESET, TipoTrama.ACK, self.timeouts.respuesta)
        if self.estado is not None and self.estado is not EstadoDU.IDLE:
            self.estado = EstadoDU.READY  # sin programa (IDLE), RESET no hace nada
        self.historial.limpiar()

    def step(self) -> Snapshot:
        """Avanza un ciclo y devuelve el snapshot (con `HALTED` si ese ciclo terminó)."""
        return self._pedir_snapshot(Comando.STEP)

    def dump(self) -> Snapshot:
        """Snapshot del estado actual, sin ejecutar nada."""
        return self._pedir_snapshot(Comando.DUMP)

    def dump_mem(self, addr: int, n: int) -> MemRange:
        """`n` palabras de la DMEM desde `addr` (en bytes, alineada a 4)."""
        self._rechazar_si_corre(Comando.DUMP_MEM)
        trama = self._pedir(
            Comando.DUMP_MEM, TipoTrama.MEM_DATA, self.timeouts.respuesta, encode_dump_mem(addr, n)
        )
        return MemRange.from_bytes(trama.payload)

    def run(self) -> Snapshot:
        """Corre hasta HALT o una ilegal y devuelve el snapshot final.

        Espera sin límite (salvo `timeouts.run`), en lecturas cortas para que un Ctrl+C
        (`KeyboardInterrupt`) pueda cortar la espera. Si eso pasa, la DU sigue en RUN: hay que
        llamar a `abort()`.
        """
        self._pedir(Comando.RUN, TipoTrama.ACK, self.timeouts.respuesta)
        self.estado = EstadoDU.RUN
        limite = None if self.timeouts.run is None else time.monotonic() + self.timeouts.run
        while True:
            try:
                return self._recibir_snapshot(Comando.RUN, self.timeouts.sondeo)
            except TimeoutError:
                if limite is not None and time.monotonic() >= limite:
                    raise TimeoutError(f"RUN no terminó en {self.timeouts.run} s") from None
            except ErrorNackDU as error:
                if error.codigo is not ErrorNack.PARIDAD:
                    raise  # en RUN, un byte con mala paridad no corta la ejecución (§7.2)

    def abort(self) -> Snapshot:
        """Corta un RUN y devuelve el snapshot con motivo `ABORTED`.

        Si el programa terminó solo justo antes, lo que llega es su snapshot final (HALTED o
        ILLEGAL) y después el `NACK(ESTADO)` del ABORT, que se descarta para que no quede como
        respuesta del próximo comando.
        """
        snapshot = self._pedir_snapshot(Comando.ABORT)
        if snapshot.motivo is not Motivo.ABORTED:
            with suppress(TimeoutError, ErrorTrama):
                self._lector.leer(self.transport, self.timeouts.respuesta)
        return snapshot

    # --- Transacciones ---------------------------------------------------------------------

    def _pedir(
        self, comando: Comando, esperado: TipoTrama, timeout: float, datos: bytes | None = None
    ) -> Trama:
        """Manda `comando` (o `datos`, si lleva argumentos) y devuelve la respuesta `esperado`."""
        self.transport.write(datos if datos is not None else encode_cmd(comando))
        return self._recibir(comando, esperado, timeout)

    def _pedir_snapshot(self, comando: Comando) -> Snapshot:
        self.transport.write(encode_cmd(comando))
        return self._recibir_snapshot(comando, self.timeouts.snapshot)

    def _recibir_snapshot(
        self, comando: Comando, timeout: float, al_historial: bool = True
    ) -> Snapshot:
        trama = self._recibir(comando, TipoTrama.SNAPSHOT, timeout)
        snapshot = Snapshot.from_bytes(trama.payload, simulado=self.transport.simulado)
        self.estado = snapshot.estado
        if al_historial:
            self.historial.agregar(snapshot)
        return snapshot

    def _recibir(self, comando: Comando, esperado: TipoTrama, timeout: float) -> Trama:
        """La próxima trama, si es del tipo `esperado`. Un NACK se convierte en `ErrorNackDU`."""
        trama = self._lector.leer(self.transport, timeout)
        if trama.tipo is TipoTrama.NACK:
            try:
                codigo = ErrorNack(trama.payload[0])
            except ValueError:
                raise ErrorPayload(
                    f"NACK con código inexistente: {trama.payload[0]:#04x}"
                ) from None
            if codigo is ErrorNack.ESTADO:
                self._averiguar_estado(comando)
            raise ErrorNackDU(comando, codigo, self.estado)
        if trama.tipo is not esperado:
            raise ErrorRespuesta(
                f"{comando.name}: se esperaba {esperado.name} y llegó {trama.tipo.name}"
            )
        return trama

    def _averiguar_estado(self, rechazado: Comando) -> None:
        """Actualiza `estado` después de un NACK(ESTADO), para que el mensaje lo nombre (AC2).

        Para LOAD, RESET, DUMP y DUMP_MEM el estado es RUN (es el único que los rechaza). Para
        STEP, RUN y ABORT hay varios posibles: se pregunta con un DUMP, que no ejecuta nada.
        """
        if rechazado in _RECHAZADOS_SOLO_EN_RUN:
            self.estado = EstadoDU.RUN
        else:
            self._consultar_estado()

    def _rechazar_si_corre(self, comando: Comando) -> None:
        """Para LOAD y DUMP_MEM: no mandarlos si la DU está (o podría estar) en RUN.

        En RUN la DU rechaza el byte de comando sin leer los argumentos (§4.1), y entonces
        toma los bytes que siguen (N, las palabras, el checksum) como comandos sueltos: un
        `0x41` en una palabra sería un ABORT. Si el estado es desconocido, se pregunta antes.
        """
        if self.estado is None:
            self._consultar_estado()
        if self.estado is EstadoDU.RUN:
            raise ErrorNackDU(comando, ErrorNack.ESTADO, EstadoDU.RUN)

    def _consultar_estado(self) -> None:
        """Pregunta el estado con un DUMP, que no ejecuta nada ni se guarda en el historial."""
        self.estado = None
        self.transport.write(encode_cmd(Comando.DUMP))
        # Un NACK del DUMP ya dejó estado = RUN; sin una respuesta clara queda None.
        with suppress(ErrorSesion, TimeoutError, ErrorTrama):
            self._recibir_snapshot(Comando.DUMP, self.timeouts.snapshot, al_historial=False)
