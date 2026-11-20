"""Carta de pipeline (US-503), sin Flet: instrucciones en filas, ciclos en columnas.

Se arma recorriendo el historial de la sesión. Cada snapshot da las 5 columnas de US-502
(`columnas_pipeline`); lo difícil es saber que la instrucción que está en EX en el ciclo t es
**la misma** que estaba en ID en el ciclo t-1, y no otra con el mismo PC (un loop).

**Identidad de una instrucción.** Una fila es una *instancia*: una instrucción en una vuelta
concreta. Entra por IF y avanza una etapa por ciclo, salvo lo que digan los riesgos del ciclo
anterior (`r`), que son las señales que decidieron cómo se movió el pipeline:

| Etapa en t | Viene de (en t-1)                                                      |
| ---------- | ---------------------------------------------------------------------- |
| IF         | IF si `r.stall` (congelada); si no, es una instancia nueva            |
| ID         | ID si `r.stall`; nada si `r.flush_if_id`; si no, IF                    |
| EX         | nada si `r.stall` (entra la burbuja) o `r.flush_id_ex`; si no, ID      |
| MEM, WB    | la etapa anterior (estas nunca se congelan)                            |

Además el PC tiene que coincidir: si no (otro mapeo en la placa, ciclos salteados), se arranca
una fila nueva en vez de pegar dos instrucciones distintas. La burbuja que mete un stall tiene su
propia fila ("burbuja") para que se vea bajar por EX, MEM y WB; las que deja un flush no.

**Solo paso a paso.** De un RUN llega solo el snapshot final: si entre dos snapshots el contador
de ciclos salta, no se puede seguir a nadie y `Carta.completa` queda en False (la vista lo dice).
"""

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field

from riscv_toolkit.protocol.snapshot import RiesgosCiclo, Snapshot
from riscv_toolkit.ui.pipeline import ETAPAS, columnas_pipeline

_IF, _ID, _EX = 0, 1, 2


@dataclass(frozen=True)
class Celda:
    """Una instancia en un ciclo: en qué etapa estaba y qué le pasó."""

    etapa: str
    congelada: bool = False  # stall: el ciclo que viene sigue en esta etapa
    anulada: bool = False  # flush: no va a terminar
    fwd: str = ""  # en EX: los operandos que llegaron por forwarding ("A", "B", "AB")


@dataclass
class Fila:
    """Una instancia. `pc` None: la burbuja de un stall."""

    pc: int | None
    texto: str
    celdas: dict[int, Celda] = field(default_factory=dict)  # índice de ciclo → celda
    halt: bool = False

    @property
    def anulada(self) -> bool:
        """Se descartó (flush): no terminó."""
        return any(c.anulada for c in self.celdas.values())


@dataclass(frozen=True)
class Carta:
    ciclos: list[int]  # el número de ciclo de cada columna (Snapshot.ciclos)
    filas: list[Fila]
    completa: bool  # False: hubo saltos (un RUN) y faltan ciclos


def _origen(etapa: int, r: RiesgosCiclo) -> int | None:
    """De qué etapa del ciclo anterior viene la instancia que está en `etapa` (tabla de arriba)."""
    if etapa == _IF:
        return _IF if r.stall else None
    if etapa == _ID:
        return _ID if r.stall else None if r.flush_if_id else _IF
    if etapa == _EX:
        return None if r.stall or r.flush_id_ex else _ID
    return etapa - 1


def carta_pipeline(snapshots: Iterable[Snapshot], imem: Sequence[int] | None) -> Carta:
    """Arma la carta desde el historial, en orden. `imem`: el programa cargado (para IF)."""
    ciclos: list[int] = []
    filas: list[Fila] = []
    completa = True
    anterior: Snapshot | None = None
    previas: list[int | None] = [None] * len(ETAPAS)  # fila de cada etapa en t-1

    for t, s in enumerate(snapshots):
        ciclos.append(s.ciclos)
        seguido = anterior is not None and s.ciclos == anterior.ciclos + 1
        if anterior is not None and not seguido:
            completa = False
        r = anterior.riesgos if seguido and anterior is not None else None
        actuales: list[int | None] = [None] * len(ETAPAS)
        # De WB a IF: si en un mismo ciclo nacen varias filas, la más vieja queda arriba.
        for k, col in reversed(list(enumerate(columnas_pipeline(s, imem)))):
            origen = _origen(k, r) if r is not None else None
            candidata = previas[origen] if origen is not None else None
            if col.burbuja:
                if candidata is not None and filas[candidata].pc is None:
                    fila = candidata  # la burbuja de un stall sigue bajando
                elif k == _EX and r is not None and r.stall:
                    filas.append(Fila(None, "burbuja"))
                    fila = len(filas) - 1
                else:
                    continue  # pipeline vacío o hueco de un flush: no es una fila
            elif candidata is not None and filas[candidata].pc == col.pc:
                fila = candidata
            else:
                filas.append(Fila(col.pc, col.texto, halt=col.halt))
                fila = len(filas) - 1
            actuales[k] = fila
            fwd = "".join(m[0] for m in col.marcas if "←" in m)  # "A ← EX/MEM" → "A"
            filas[fila].celdas[t] = Celda(ETAPAS[k], col.congelada, col.anulada, fwd)
        anterior, previas = s, actuales

    return Carta(ciclos, filas, completa)
