"""Lo que sale de recorrer el historial (páginas Historial, Registros, Memoria, Verificar y
Resumen), sin Flet: se prueba con pytest.

**Quién escribió qué.** Entre el snapshot `a` (ciclo t) y el siguiente `b` (ciclo t+1):
- un registro lo escribe la instrucción que en `a` está en WB (`a.mem_wb`): el banco se
  escribe en el flanco al final del ciclo;
- una palabra de memoria la escribe el store que en `a` está en MEM (`a.ex_mem`).

Solo vale si `b` es el ciclo siguiente a `a` (paso a paso). Después de un RUN hay un salto de
ciclos y no se sabe quién fue: se devuelve None.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from itertools import pairwise

from riscv_toolkit.disasm.disassembler import desensamblar
from riscv_toolkit.isa.instrucciones import HALT_OPCODE
from riscv_toolkit.protocol.snapshot import LatchMEMWB, Snapshot
from riscv_toolkit.session.diff import diff
from riscv_toolkit.ui.pipeline import columnas_pipeline

# Marcas de un ciclo, con los mismos nombres que los colores de `tema.RIESGO`.
STALL, FLUSH, FWD_A, FWD_B, FIN = "st", "fl", "fa", "fb", "ht"


def eventos(s: Snapshot) -> tuple[str, ...]:
    """Qué pasó en el ciclo de `s`: stall, flush, forwarding A/B, terminó."""
    r = s.riesgos
    marcas = [
        (STALL, r.stall),
        (FLUSH, r.flush_if_id or r.flush_id_ex),
        (FWD_A, r.fwd_a != 0),
        (FWD_B, r.fwd_b != 0),
        (FIN, s.motivo is not None),
    ]
    return tuple(m for m, activo in marcas if activo)


def valor_wb(wb: LatchMEMWB) -> int:
    """Lo que se escribe en rd: según `result_src`, 00 la ALU, 01 la memoria, 10 PC+4."""
    return {1: wb.mem_data, 2: wb.pc_plus4}.get(wb.result_src, wb.alu_result)


def _texto_wb(s: Snapshot) -> str:
    return desensamblar(s.mem_wb.instr, s.mem_wb.pc_plus4 - 4)


def _texto_mem(s: Snapshot) -> str:
    return desensamblar(s.ex_mem.instr, s.ex_mem.pc_plus4 - 4)


def escribe_al_final(s: Snapshot) -> tuple[int, int, str] | None:
    """(rd, valor, instrucción) si la de WB escribe un registro al final de este ciclo."""
    wb = s.mem_wb
    if not (wb.valid and wb.reg_write and wb.rd):
        return None
    return wb.rd, valor_wb(wb), _texto_wb(s)


def _seguidos(a: Snapshot | None, b: Snapshot) -> bool:
    return a is not None and b.ciclos == a.ciclos + 1


def _escribio_reg(a: Snapshot, b: Snapshot, reg: int) -> str | None:
    """La instrucción de WB en `a`, si es la que escribió `reg` (reg_write y el mismo rd).

    Si no cierra (salto de ciclos por un RUN), None: mejor "no se sabe" que culpar a la
    instrucción equivocada.
    """
    wb = a.mem_wb
    if _seguidos(a, b) and wb.valid and wb.reg_write and wb.rd == reg:
        return _texto_wb(a)
    return None


def _escribio_mem(a: Snapshot, b: Snapshot) -> str | None:
    """El store de MEM en `a`, si hay uno (mem_write) y `b` es el ciclo siguiente."""
    mem = a.ex_mem
    if _seguidos(a, b) and mem.valid and mem.mem_write:
        return _texto_mem(a)
    return None


@dataclass(frozen=True)
class CambioRegistro:
    reg: int
    antes: int
    despues: int
    quien: str | None  # la instrucción que lo escribió; None si no se sabe
    ciclo: int  # en qué ciclo estaba en WB (el de `anterior`)


def cambios_registros(anterior: Snapshot | None, actual: Snapshot | None) -> list[CambioRegistro]:
    """Los registros que cambiaron de `anterior` a `actual`, con quién los escribió."""
    if anterior is None or actual is None:
        return []
    return [
        CambioRegistro(n, antes, despues, _escribio_reg(anterior, actual, n), anterior.ciclos)
        for n, (antes, despues) in diff(anterior, actual).regs.items()
    ]


def ultimas_escrituras(snapshots: Sequence[Snapshot]) -> dict[int, str]:
    """Dirección → "sw x5, 0(x0) · ciclo 7": el último store que la escribió.

    Si cambió en un salto de ciclos, "durante un RUN"; si no hay un store en MEM, "—".
    """
    escrituras: dict[int, str] = {}
    for a, b in pairwise(snapshots):
        quien = _escribio_mem(a, b)
        for direccion in diff(a, b).memoria:
            escrituras[direccion] = (
                f"{quien} · ciclo {a.ciclos}" if quien is not None
                else "—" if _seguidos(a, b) else "durante un RUN"
            )  # fmt: skip
    return escrituras


def origen_de(snapshots: Sequence[Snapshot], que: str) -> tuple[int, str] | None:
    """Para Verificar: (índice en el historial, instrucción) de la última escritura de `que`.

    `que`: "x5" o "[0x010]", como `Diferencia.que`. El índice es el del ciclo en que la
    instrucción estaba en WB (registro) o en MEM (memoria): ir ahí muestra quién fue.
    """
    for i in range(len(snapshots) - 1, 0, -1):
        a, b = snapshots[i - 1], snapshots[i]
        cambios = diff(a, b)
        quien = None
        if que.startswith("x") and int(que[1:]) in cambios.regs:
            quien = _escribio_reg(a, b, int(que[1:]))
        elif que.startswith("[") and int(que[1:-1], 16) in cambios.memoria:
            quien = _escribio_mem(a, b)
        else:
            continue
        return (i - 1, quien) if quien is not None else None
    return None


# --- Tabla de la página Historial ---------------------------------------------------------


@dataclass(frozen=True)
class FilaHistorial:
    ciclo: int
    pc: int
    etapas: tuple[str, ...]  # el mnemónico en IF…WB; "—" una burbuja
    eventos: tuple[str, ...]
    cambios: str  # "x1 ← 0x10 · M[0x010] ← 0x5"


def filas_historial(
    snapshots: Sequence[Snapshot], imem: Sequence[int] | None
) -> list[FilaHistorial]:
    filas = []
    for i, s in enumerate(snapshots):
        etapas = tuple("—" if c.burbuja else c.texto.split()[0] for c in columnas_pipeline(s, imem))
        cambios = diff(snapshots[i - 1], s) if i > 0 else None
        partes = []
        if cambios is not None:
            partes += [f"x{n} ← 0x{v:x}" for n, (_, v) in cambios.regs.items()]
            partes += [f"M[0x{d:03x}] ← 0x{v:x}" for d, (_, v) in cambios.memoria.items()]
        filas.append(FilaHistorial(s.ciclos, s.pc, etapas, eventos(s), " · ".join(partes)))
    return filas


# --- Resumen ------------------------------------------------------------------------------

# Opcode → clase, para la mezcla de instrucciones.
_CLASES = {
    0b0010011: "ALU con inmediato",
    0b0110011: "ALU registro",
    0b0000011: "Load",
    0b0100011: "Store",
    0b1100011: "Branch",
    0b1101111: "Saltos (jal, jalr)",
    0b1100111: "Saltos (jal, jalr)",
    0b0110111: "lui",
    HALT_OPCODE: "HALT",
}


@dataclass(frozen=True)
class Resumen:
    ciclos: int  # el contador de la DU (incluye los ciclos de un RUN)
    vistos: int  # los que se vieron paso a paso: sobre estos se hacen las cuentas
    instrucciones: int  # las que terminaron (pasaron por WB), sin contar HALT
    stalls: int
    flushes: int  # instrucciones descartadas
    forwardings: int  # operandos adelantados (A y B cuentan aparte)
    ocupadas: list[int]  # etapas con instrucción, por snapshot
    eventos: list[tuple[str, ...]]  # por snapshot
    reparto: dict[str, int]  # en qué se fueron los ciclos
    mezcla: dict[str, int]  # clase → cuántas terminaron
    completo: bool  # False: hubo un RUN y faltan ciclos

    @property
    def cpi(self) -> float | None:
        return self.vistos / self.instrucciones if self.instrucciones else None


def resumen(snapshots: Sequence[Snapshot], imem: Sequence[int] | None) -> Resumen:
    """Las cuentas de la página Resumen.

    El reparto de ciclos de un pipeline de 5 etapas: cada instrucción terminada es un ciclo
    útil, cada stall y cada instrucción descartada es un ciclo perdido, y lo que queda es
    llenar y vaciar el pipeline (4 ciclos por corrida, más lo que tarde en arrancar).

    Después de un RUN solo llega el snapshot final: las cuentas (y el CPI) son solo de los
    ciclos vistos paso a paso. Mezclar el contador de la DU con las instrucciones contadas
    en los snapshots daba un CPI sin sentido (271 ciclos / 5 instrucciones).
    """
    instrucciones = stalls = flushes = forwardings = vistos = 0
    mezcla: dict[str, int] = {}
    completo = True
    for i, s in enumerate(snapshots):
        if i > 0 and not _seguidos(snapshots[i - 1], s):
            completo = False
            continue  # el snapshot final de un RUN: su ciclo no se vio llegar
        vistos += i > 0
        r = s.riesgos
        stalls += r.stall
        flushes += r.flush_if_id + r.flush_id_ex
        forwardings += (r.fwd_a != 0) + (r.fwd_b != 0)
        wb = s.mem_wb
        if wb.valid:
            clase = _CLASES.get(wb.instr & 0x7F, "Ilegal")
            mezcla[clase] = mezcla.get(clase, 0) + 1
            instrucciones += not (wb.halt or wb.illegal)
    ciclos = snapshots[-1].ciclos if snapshots else 0
    if completo:
        vistos = ciclos  # paso a paso desde el principio: también cuenta el arranque
    llenado = max(0, vistos - instrucciones - stalls - flushes)
    return Resumen(
        ciclos=ciclos,
        vistos=vistos,
        instrucciones=instrucciones,
        stalls=stalls,
        flushes=flushes,
        forwardings=forwardings,
        ocupadas=[sum(not c.burbuja for c in columnas_pipeline(s, imem)) for s in snapshots],
        eventos=[eventos(s) for s in snapshots],
        reparto={
            "Útiles": instrucciones,
            "Llenar y vaciar": llenado,
            "Stall": stalls,
            "Flush": flushes,
        },
        mezcla=dict(sorted(mezcla.items(), key=lambda kv: -kv[1])),
        completo=completo,
    )
