"""Estado de la GUI, independiente de Flet (US-501, ADR-012).

Acá se decide qué se puede hacer; las vistas solo copian el resultado a los controles. Así la
regla vive en un solo lugar, se prueba con pytest sin abrir ventanas, y los botones y los
atajos de teclado no pueden contradecirse (AC3). No importa Flet (PRD §4.3).
"""

from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum, auto

from riscv_toolkit.protocol.comandos import EstadoDU, Motivo
from riscv_toolkit.protocol.snapshot import Snapshot


class Accion(Enum):
    """Los controles de ejecución. "Paso N veces" usa la misma regla que PASO."""

    CARGAR = auto()
    CORRER = auto()
    PASO = auto()
    ABORTAR = auto()
    RESET = auto()


@dataclass(frozen=True)
class EstadoUI:
    """Lo que la GUI sabe en un momento dado. Inmutable: cada cambio arma uno nuevo."""

    conectado: bool = False
    # Estado de la DU según la última respuesta; None si todavía no se sabe (recién conectado).
    estado_du: EstadoDU | None = None
    # Hay un programa ensamblado sin errores y el texto no cambió desde entonces (AC2).
    imagen_valida: bool = False
    # Hay una operación en curso en el worker: STEP, LOAD, el RUN mismo, … (paso 3).
    ocupado: bool = False


def acciones_habilitadas(estado: EstadoUI) -> frozenset[Accion]:
    """Las acciones que se pueden pedir ahora: espejo de R-DU-1 (protocolo §4.1).

    | Estado de la DU         | Habilitadas                                     |
    | ----------------------- | ----------------------------------------------- |
    | IDLE, HALTED            | CARGAR, RESET                                   |
    | READY, STEPPING         | CARGAR, CORRER, PASO, RESET                     |
    | RUN                     | ABORTAR                                         |
    | LOADING, DUMPING, None  | ninguna (transitorios, o todavía no se sabe)    |

    Además:
    - Desconectado: ninguna.
    - CARGAR exige `imagen_valida` (AC2).
    - `ocupado`: ninguna, salvo ABORTAR en RUN. Durante un RUN el worker está ocupado
      esperando el snapshot final, y Abortar es justo lo que tiene que poder apretarse (AC4).
    """
    if not estado.conectado:
        return frozenset()
    # Antes que `ocupado`: en RUN el worker siempre está ocupado esperando, y ABORT es la
    # única salida.
    if estado.estado_du is EstadoDU.RUN:
        return frozenset({Accion.ABORTAR})
    if estado.ocupado:
        return frozenset()

    match estado.estado_du:
        case EstadoDU.IDLE | EstadoDU.HALTED:
            acciones = {Accion.CARGAR, Accion.RESET}
        case EstadoDU.READY | EstadoDU.STEPPING:
            acciones = {Accion.CARGAR, Accion.CORRER, Accion.PASO, Accion.RESET}
        case _:  # LOADING, DUMPING o None
            return frozenset()
    if not estado.imagen_valida:
        acciones.discard(Accion.CARGAR)
    return frozenset(acciones)


# --- Línea en ejecución (AC5 y AC6) --------------------------------------------------------


class Etapa(Enum):
    """Qué instrucción se sigue en el listado: la que entra (IF) o la que termina (WB)."""

    IF = auto()
    WB = auto()


def pc_resaltado(snapshot: Snapshot, etapa: Etapa) -> int | None:
    """PC de la instrucción a resaltar, o None si no hay ninguna (burbuja o ya terminó).

    - IF: el registro PC, que es lo que se está buscando en ese ciclo.
    - WB: la del latch MEM/WB (`pc_plus4 - 4`), si no es burbuja.
    - Terminó por ILLEGAL (AC6): la instrucción ilegal, sin importar la etapa elegida. Si
      todavía está en MEM/WB se toma de ahí; si no, del PC (el golden model se queda en ella).
    - Terminó por HALT o ABORT: ninguna.
    """
    wb = snapshot.mem_wb
    if snapshot.motivo is Motivo.ILLEGAL:
        # shortcut: en la placa el PC puede quedar unos ciclos más adelante si MEM/WB ya se
        # vació; verificar con el núcleo real (Hito 3) y, si hace falta, que la DU lo guarde.
        return wb.pc_plus4 - 4 if wb.valid and wb.illegal else snapshot.pc
    if snapshot.motivo is not None:
        return None
    if etapa is Etapa.IF:
        return snapshot.pc
    return wb.pc_plus4 - 4 if wb.valid else None


def contar_riesgos(snapshots: Iterable[Snapshot]) -> tuple[int, int]:
    """(stalls, flushes) acumulados. Un ciclo con flush en IF/ID y en ID/EX cuenta uno.

    Solo tiene sentido paso a paso: de un RUN llega únicamente el snapshot final.
    """
    stalls = flushes = 0
    for s in snapshots:
        stalls += s.riesgos.stall
        flushes += s.riesgos.flush_if_id or s.riesgos.flush_id_ex
    return stalls, flushes


# --- Posiciones en el texto del editor -----------------------------------------------------


def linea_de(texto: str, offset: int) -> int:
    """Número de línea (desde 1) del carácter en `offset`."""
    return texto.count("\n", 0, offset) + 1


def rango_de_linea(texto: str, linea: int) -> tuple[int, int]:
    """(inicio, fin) de la línea `linea` (desde 1), sin el salto final. Fuera de rango: el
    final del texto, para que ir a una línea que ya no existe no rompa nada."""
    lineas = texto.split("\n")
    if not 1 <= linea <= len(lineas):
        return len(texto), len(texto)
    inicio = sum(len(anterior) + 1 for anterior in lineas[: linea - 1])
    return inicio, inicio + len(lineas[linea - 1])
