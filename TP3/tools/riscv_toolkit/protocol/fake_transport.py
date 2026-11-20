"""Placa simulada: el protocolo de la Debug Unit respondido por el golden model (US-409).

Recibe los mismos bytes que la placa y responde las mismas tramas, con las mismas reglas de
estado (R-DU-1, protocolo §4.1 y §5), pero el procesador es el ISS. Sirve para desarrollar la
sesión, la CLI y la GUI sin hardware, y para probarlas en el CI.

Diferencias con la placa (por eso el snapshot sale con `simulado = True`):
- Un `STEP` ejecuta una **instrucción**, no un ciclo; `ciclos` cuenta instrucciones.
- No hay riesgos: el byte de riesgos siempre es 0.
- Los latches son una aproximación: en `STEPPING`, IF/ID tiene la próxima instrucción y ID/EX,
  EX/MEM y MEM/WB las tres anteriores, ya ejecutadas (con `pc`, `pc_plus4`, `instr` y `valid`;
  el resto de los campos en 0). En los demás estados el pipeline está vacío.
- `RUN` corre de una, dentro de `write`: si el programa no termina en `max_instr`
  instrucciones queda en `RUN` hasta un `ABORT`, como un loop infinito en la placa.
- Sin timeouts de recepción: un comando con argumentos incompletos espera al próximo `write`.
  Un `LOAD` con `N` inválido descarta todo lo recibido (la placa: hasta 100 ms de silencio, §7.2).
"""

import time
from collections import deque

from riscv_toolkit.iss.golden_model import GoldenModel
from riscv_toolkit.iss.golden_model import Motivo as MotivoISS
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
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    MemRange,
    RiesgosCiclo,
    Snapshot,
)

_MAX_INSTR = 100_000  # como rvsim: un programa de la suite corre en menos de mil
_MOTIVOS = {MotivoISS.HALTED: Motivo.HALTED, MotivoISS.ILLEGAL: Motivo.ILLEGAL}
_PUEDE_EJECUTAR = {EstadoDU.READY, EstadoDU.STEPPING}  # RUN y STEP (§4.1)


class FakeTransport:
    """`Transport` que responde como la Debug Unit, con el golden model como procesador."""

    simulado = True

    def __init__(self, max_instr: int = _MAX_INSTR) -> None:
        self._max_instr = max_instr
        self._entrada = bytearray()  # bytes recibidos que todavía no formaron un comando
        self._salida = bytearray()  # tramas listas para `read`
        self._programa: list[int] = []
        self._historia: deque[int] = deque(maxlen=3)  # PC de las últimas ejecutadas
        # Los asigna _reiniciar (LOAD, RESET y el encendido):
        self._modelo: GoldenModel
        self._estado: EstadoDU
        self._motivo: Motivo
        self._ciclos: int
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
                self._terminar(Motivo.ABORTED)
            else:
                self._nack(ErrorNack.ESTADO)
        elif comando is Comando.RESET:
            if self._estado is not EstadoDU.IDLE:  # sin programa, RESET no hace nada (ADR-009)
                self._reiniciar()
            self._responder(TipoTrama.ACK)
        elif comando is Comando.DUMP:
            self._enviar_snapshot()
        elif comando is Comando.STEP and self._estado in _PUEDE_EJECUTAR:
            if not self._ejecutar_una():  # si terminó, _terminar ya mandó el snapshot final
                self._estado = EstadoDU.STEPPING
                self._enviar_snapshot()
        elif comando is Comando.RUN and self._estado in _PUEDE_EJECUTAR:
            self._responder(TipoTrama.ACK)
            self._estado = EstadoDU.RUN
            for _ in range(self._max_instr):
                if self._ejecutar_una():
                    return
        else:  # STEP o RUN sin programa o ya terminado, ABORT fuera de RUN
            self._nack(ErrorNack.ESTADO)

    # --- Ejecución -------------------------------------------------------------------------

    def _ejecutar_una(self) -> bool:
        """Una instrucción en el ISS. Si con ella terminó, manda el snapshot final y da True."""
        pc = self._modelo.pc
        motivo = self._modelo.step()
        self._ciclos += 1
        if motivo is None:
            self._historia.appendleft(pc)
            return False
        self._terminar(_MOTIVOS[motivo])
        return True

    def _terminar(self, motivo: Motivo) -> None:
        self._estado = EstadoDU.HALTED
        self._motivo = motivo
        self._historia.clear()  # al terminar, el pipeline queda vacío
        self._enviar_snapshot()

    def _reiniciar(self) -> None:
        """Programa cargado y todo lo demás limpio: el estado después de LOAD o RESET."""
        self._modelo = GoldenModel(self._programa)
        self._estado = EstadoDU.READY
        self._motivo = Motivo.NINGUNO
        self._ciclos = 0
        self._historia.clear()

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
        m = self._modelo

        def instr(pc: int) -> int:
            return m.imem[(pc // 4) % len(m.imem)]

        if_id, id_ex, ex_mem, mem_wb = LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB()
        if self._estado is EstadoDU.STEPPING:
            if_id = LatchIFID(m.pc, m.pc + 4, instr(m.pc), valid=True)
        historia = list(self._historia)  # la más reciente primero: ID/EX, EX/MEM, MEM/WB
        if len(historia) > 0:
            pc = historia[0]
            id_ex = LatchIDEX(pc=pc, pc_plus4=pc + 4, valid=True, instr=instr(pc))
        if len(historia) > 1:
            ex_mem = LatchEXMEM(pc_plus4=historia[1] + 4, valid=True, instr=instr(historia[1]))
        if len(historia) > 2:
            mem_wb = LatchMEMWB(pc_plus4=historia[2] + 4, valid=True, instr=instr(historia[2]))
        return Snapshot(
            estado=self._estado,
            motivo=None if self._motivo is Motivo.NINGUNO else self._motivo,
            ciclos=self._ciclos,
            pc=m.pc,
            riesgos=RiesgosCiclo(),
            regs=tuple(m.regs),
            if_id=if_id,
            id_ex=id_ex,
            ex_mem=ex_mem,
            mem_wb=mem_wb,
            mem_usada={
                d: int.from_bytes(m.dmem[d : d + 4], "little") for d in sorted(m.mem_escrita)
            },
            simulado=True,
        )
