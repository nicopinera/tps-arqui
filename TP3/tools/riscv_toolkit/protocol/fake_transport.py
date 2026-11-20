"""Placa simulada: el protocolo de la Debug Unit respondido por el modelo del pipeline (US-409).

Recibe los mismos bytes que la placa y responde las mismas tramas, con las mismas reglas de
estado (R-DU-1, protocolo §4.1 y §5). El procesador es `ModeloPipeline` (agregado US-306): el
pipeline de 5 etapas ciclo a ciclo, con forwarding, Hazard Unit y flush. Sirve para
desarrollar la sesión, la CLI y la GUI sin hardware, y para probarlas en el CI.

Como en la placa: un `STEP` es un ciclo, `ciclos` cuenta ciclos, los latches y el byte de
riesgos son los del modelo, y `ABORT` prende `stop_fetch` y espera a que el pipeline se vacíe.

Diferencias con la placa (por eso el snapshot sale con `simulado = True`):
- `RUN` corre de una, dentro de `write`: si el programa no termina en `max_ciclos` ciclos
  queda en `RUN` hasta un `ABORT`, como un loop infinito en la placa.
- Sin timeouts de recepción: un comando con argumentos incompletos espera al próximo `write`.
  Un `LOAD` con `N` inválido descarta todo lo recibido (la placa: hasta 100 ms de silencio, §7.2).
"""

import time
from dataclasses import replace

from riscv_toolkit.iss.pipeline_model import ModeloPipeline
from riscv_toolkit.protocol.codec import checksum, encode_trama
from riscv_toolkit.protocol.comandos import (
    DMEM_DEPTH,
    IMEM_DEPTH,
    PROTO_VERSION,
    Comando,
    ErrorNack,
    EstadoDU,
    Motivo,
    TipoTrama,
)
from riscv_toolkit.protocol.snapshot import MemRange, Snapshot

_MAX_CICLOS = 200_000  # un programa de la suite corre en menos de mil
_PUEDE_EJECUTAR = {EstadoDU.READY, EstadoDU.STEPPING}  # RUN y STEP (§4.1)


class FakeTransport:
    """`Transport` que responde como la Debug Unit, con el modelo del pipeline como núcleo."""

    simulado = True

    def __init__(self, max_ciclos: int = _MAX_CICLOS) -> None:
        self._max_ciclos = max_ciclos
        self._entrada = bytearray()  # bytes recibidos que todavía no formaron un comando
        self._salida = bytearray()  # tramas listas para `read`
        self._programa: list[int] = []
        # Los asigna _reiniciar (LOAD, RESET y el encendido):
        self._modelo: ModeloPipeline
        self._estado: EstadoDU
        self._motivo: Motivo
        self._fallo_load(None)  # arranca como después del encendido: IDLE, IMEM con HALT

    # --- Transport -------------------------------------------------------------------------

    def write(self, datos: bytes) -> None:
        self._entrada += datos
        self._procesar()

    def read(self, n: int, timeout: float | None) -> bytes:
        """Lo que haya respondido hasta ahora.

        Si no hay nada, nadie más va a responder (no hay otro hilo): duerme `timeout` como la
        placa que no contesta, así quien espera en un bucle (`RUN` sin fin) no gira en vacío.
        """
        if not self._salida and timeout:
            time.sleep(timeout)
        datos = bytes(self._salida[:n])
        del self._salida[:n]
        return datos

    def close(self) -> None:
        self._entrada.clear()
        self._salida.clear()

    # --- Recepción de comandos -------------------------------------------------------------

    def _procesar(self) -> None:
        """Interpreta todos los comandos completos de `_entrada`."""
        while self._entrada:
            cmd = self._entrada[0]
            en_run = self._estado is EstadoDU.RUN  # en RUN, LOAD y DUMP_MEM no leen argumentos
            if cmd == Comando.LOAD and not en_run:
                if not self._recibir_load():
                    return
            elif cmd == Comando.DUMP_MEM and not en_run:
                if len(self._entrada) < 5:
                    return
                addr = int.from_bytes(self._entrada[1:3], "little")
                n = int.from_bytes(self._entrada[3:5], "little")
                del self._entrada[:5]
                self._dump_mem(addr, n)
            else:
                del self._entrada[0]
                self._comando(cmd)

    def _recibir_load(self) -> bool:
        """Procesa un `LOAD` si llegó entero. False si faltan bytes."""
        if len(self._entrada) < 3:
            return False
        n = int.from_bytes(self._entrada[1:3], "little")
        if not 1 <= n <= IMEM_DEPTH:
            self._entrada.clear()  # drena: el resto eran las palabras de este LOAD
            self._fallo_load(ErrorNack.TAMANO)
            return True
        total = 3 + 4 * n + 1
        if len(self._entrada) < total:
            return False
        trama = bytes(self._entrada[:total])
        del self._entrada[:total]
        if checksum(trama[1:]) != 0:
            self._fallo_load(ErrorNack.CHECKSUM)
            return True
        self._programa = [
            int.from_bytes(trama[i : i + 4], "little") for i in range(3, total - 1, 4)
        ]
        self._reiniciar()
        self._responder(TipoTrama.ACK)
        return True

    def _comando(self, cmd: int) -> None:
        """Comando sin argumentos (o LOAD / DUMP_MEM en RUN, que no los leen)."""
        if cmd not in Comando:
            self._nack(ErrorNack.DESCONOCIDO)
            return
        comando = Comando(cmd)
        if comando is Comando.PING:
            self._responder(TipoTrama.PING_INFO, bytes([PROTO_VERSION]))
        elif self._estado is EstadoDU.RUN:
            if comando is Comando.ABORT:
                self._abortar()
            else:
                self._nack(ErrorNack.ESTADO)
        elif comando is Comando.RESET:
            if self._estado is not EstadoDU.IDLE:  # sin programa, RESET no hace nada (ADR-009)
                self._reiniciar()
            self._responder(TipoTrama.ACK)
        elif comando is Comando.DUMP:
            self._enviar_snapshot()
        elif comando is Comando.STEP and self._estado in _PUEDE_EJECUTAR:
            if not self._ciclo():  # si terminó, _terminar ya mandó el snapshot final
                self._estado = EstadoDU.STEPPING
                self._enviar_snapshot()
        elif comando is Comando.RUN and self._estado in _PUEDE_EJECUTAR:
            self._responder(TipoTrama.ACK)
            self._estado = EstadoDU.RUN
            for _ in range(self._max_ciclos):
                if self._ciclo():
                    return
        else:  # STEP o RUN sin programa o ya terminado, ABORT fuera de RUN
            self._nack(ErrorNack.ESTADO)

    # --- Ejecución -------------------------------------------------------------------------

    def _ciclo(self) -> bool:
        """Un ciclo del núcleo. Si con él terminó, manda el snapshot final y da True."""
        self._modelo.ciclo()
        if self._modelo.motivo is None:
            return False
        self._terminar(self._modelo.motivo)
        return True

    def _abortar(self) -> None:
        """ABORT (R-EJ-5, ADR-010): `stop_fetch` hasta que los 4 latches estén vacíos.

        Lo que ya estaba en EX, MEM y WB termina; si era un HALT, el motivo es HALTED.
        """
        modelo = self._modelo
        modelo.stop_fetch = True
        while not modelo.vacio and modelo.motivo is None:
            modelo.ciclo()
        self._terminar(modelo.motivo or Motivo.ABORTED)

    def _terminar(self, motivo: Motivo) -> None:
        self._estado = EstadoDU.HALTED
        self._motivo = motivo
        self._enviar_snapshot()

    def _reiniciar(self) -> None:
        """Programa cargado y todo lo demás limpio: el estado después de LOAD o RESET."""
        self._modelo = ModeloPipeline(self._programa)
        self._estado = EstadoDU.READY
        self._motivo = Motivo.NINGUNO

    def _fallo_load(self, error: ErrorNack | None) -> None:
        """IDLE con la IMEM llena de HALT (R-DU-4); responde el NACK si hay error."""
        self._programa = []
        self._reiniciar()
        self._estado = EstadoDU.IDLE
        if error is not None:
            self._nack(error)

    # --- Respuestas ------------------------------------------------------------------------

    def _responder(self, tipo: TipoTrama, payload: bytes = b"") -> None:
        self._salida += encode_trama(tipo, payload)

    def _nack(self, error: ErrorNack) -> None:
        self._responder(TipoTrama.NACK, bytes([error]))

    def _dump_mem(self, addr: int, n: int) -> None:
        if addr % 4 != 0 or n < 1 or addr // 4 + n > DMEM_DEPTH:
            self._nack(ErrorNack.RANGO)
            return
        dmem = self._modelo.dmem
        palabras = tuple(
            int.from_bytes(dmem[d : d + 4], "little") for d in range(addr, addr + 4 * n, 4)
        )
        self._responder(TipoTrama.MEM_DATA, MemRange(addr, palabras).to_bytes())

    def _enviar_snapshot(self) -> None:
        self._responder(TipoTrama.SNAPSHOT, self._snapshot().to_bytes())

    def _snapshot(self) -> Snapshot:
        return replace(
            self._modelo.snapshot(self._estado),
            motivo=None if self._motivo is Motivo.NINGUNO else self._motivo,
        )
