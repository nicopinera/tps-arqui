"""Qué muestra la vista del pipeline (US-502), sin Flet: se prueba con pytest.

**De dónde sale cada columna.** El snapshot no tiene un latch "antes" de IF:

| Columna | Instrucción                                                              |
| ------- | ------------------------------------------------------------------------ |
| IF      | la de `Snapshot.pc` en la imagen cargada (la IMEM no cambia al ejecutar) |
| ID      | `instr` de IF/ID                                                         |
| EX      | `instr` de ID/EX                                                         |
| MEM     | `instr` de EX/MEM                                                        |
| WB      | `instr` de MEM/WB                                                        |

Es fácil confundirlo: el latch IF/ID **no** es la etapa IF, es lo que IF le dejó a ID.

**Riesgos.** `RiesgosCiclo` son las salidas de la Hazard Unit y la Forwarding Unit con el
núcleo congelado: dicen qué va a pasar con lo que está en el pipeline **ahora**.
- `stall`: IF e ID se congelan (en el ciclo que viene muestran lo mismo) y entra una burbuja
  a EX.
- `flush_if_id`: la instrucción de IF se descarta (`jal` en ID, o redirección desde EX).
- `flush_id_ex`: la de ID se descarta (branch tomado o `jalr` en EX).
- `fwd_a`/`fwd_b`: de dónde toma EX cada operando; la etapa fuente también se marca.

shortcut: esta lectura (combinacional, del ciclo congelado) es la de `riscv_core.md`; verificarla
contra el núcleo real (Hito 3) con `load_use.asm`, `branch_taken.asm` y `fwd_ex_mem.asm`.
"""

from collections.abc import Sequence
from dataclasses import dataclass, fields, replace

from riscv_toolkit.disasm.disassembler import desensamblar
from riscv_toolkit.isa.formatos import decode_j
from riscv_toolkit.isa.instrucciones import HALT_OPCODE, HALT_WORD, identificar
from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    Snapshot,
)

ETAPAS = ("IF", "ID", "EX", "MEM", "WB")
Latch = LatchIFID | LatchIDEX | LatchEXMEM | LatchMEMWB
LATCHES = ("IF/ID", "ID/EX", "EX/MEM", "MEM/WB")
# Columna → el latch que guarda su instrucción. IF no tiene: sale del PC.
LATCH_DE_COLUMNA = {"ID": "IF/ID", "EX": "ID/EX", "MEM": "EX/MEM", "WB": "MEM/WB"}
_FUENTE_FWD = {1: ("WB", "MEM/WB"), 2: ("MEM", "EX/MEM")}  # fwd_x → (columna, latch)


@dataclass(frozen=True)
class Columna:
    """Una etapa del pipeline en este ciclo."""

    etapa: str
    pc: int | None = None  # None: burbuja, o una IF sin programa conocido
    texto: str = ""  # instrucción desensamblada ("" en una burbuja)
    burbuja: bool = True  # `valid = 0`: no hay instrucción
    halt: bool = False
    ilegal: bool = False
    anulada: bool = False  # flush: no va a terminar (se tacha)
    congelada: bool = False  # stall: el ciclo que viene sigue acá
    marcas: tuple[str, ...] = ()  # forwarding: "A ← EX/MEM" en EX, "→ A" en la fuente
    palabra: int | None = None  # la instrucción en binario (None: burbuja o desconocida)


def _columna(etapa: str, valid: bool, pc: int, instr: int) -> Columna:
    if not valid:
        return Columna(etapa)
    halt = instr & 0x7F == HALT_OPCODE
    return Columna(
        etapa,
        pc=pc,
        texto=desensamblar(instr, pc),
        burbuja=False,
        palabra=instr,
        halt=halt,
        ilegal=not halt and identificar(instr) is None,
    )


def _columna_if(snapshot: Snapshot, imem: Sequence[int] | None) -> Columna:
    if snapshot.estado in (EstadoDU.IDLE, EstadoDU.HALTED):
        return Columna("IF")  # sin programa, o terminó: el pipeline está vacío (protocolo §5)
    if imem is None:  # conectados a una placa que ya tenía un programa: no sabemos cuál
        return Columna("IF", pc=snapshot.pc, texto="?", burbuja=False)
    indice = snapshot.pc // 4
    palabra = imem[indice] if indice < len(imem) else HALT_WORD  # el resto de la IMEM es HALT
    return _columna("IF", True, snapshot.pc, palabra)


def columnas_pipeline(snapshot: Snapshot, imem: Sequence[int] | None) -> list[Columna]:
    """Las 5 columnas IF…WB con sus marcas. `imem`: las palabras del programa cargado."""
    s = snapshot
    cols = {
        "IF": _columna_if(s, imem),
        "ID": _columna("ID", s.if_id.valid, s.if_id.pc, s.if_id.instr),
        "EX": _columna("EX", s.id_ex.valid, s.id_ex.pc, s.id_ex.instr),
        # EX/MEM y MEM/WB no guardan el PC: se deduce de pc_plus4.
        "MEM": _columna("MEM", s.ex_mem.valid, s.ex_mem.pc_plus4 - 4, s.ex_mem.instr),
        "WB": _columna("WB", s.mem_wb.valid, s.mem_wb.pc_plus4 - 4, s.mem_wb.instr),
    }
    r = s.riesgos
    if r.stall:
        cols["IF"] = replace(cols["IF"], congelada=True)
        cols["ID"] = replace(cols["ID"], congelada=True)
    if r.flush_if_id:
        cols["IF"] = replace(cols["IF"], anulada=True)
    if r.flush_id_ex:
        cols["ID"] = replace(cols["ID"], anulada=True)
    for operando, fwd in (("A", r.fwd_a), ("B", r.fwd_b)):
        if fwd in _FUENTE_FWD:
            columna, latch = _FUENTE_FWD[fwd]
            cols["EX"] = replace(cols["EX"], marcas=(*cols["EX"].marcas, f"{operando} ← {latch}"))
            cols[columna] = replace(cols[columna], marcas=(*cols[columna].marcas, f"→ {operando}"))
    return [cols[e] for e in ETAPAS]


def latches(snapshot: Snapshot | None) -> dict[str, Latch]:
    """Los 4 latches por nombre; sin snapshot, vacíos (todo en 0)."""
    if snapshot is None:
        return {"IF/ID": LatchIFID(), "ID/EX": LatchIDEX(), "EX/MEM": LatchEXMEM(),
                "MEM/WB": LatchMEMWB()}  # fmt: skip
    return {
        "IF/ID": snapshot.if_id,
        "ID/EX": snapshot.id_ex,
        "EX/MEM": snapshot.ex_mem,
        "MEM/WB": snapshot.mem_wb,
    }


# Campos de 32 bits: se muestran con 8 dígitos hex. El resto son campos chicos o banderas.
_DE_32_BITS = {
    "pc", "pc_plus4", "rs1_data", "rs2_data", "imm", "alu_result", "store_data", "mem_data",
    "instr",
}  # fmt: skip


def campos_latch(latch: Latch) -> list[tuple[str, str, str]]:
    """(campo, hex, decimal) de cada campo del latch, en el orden del protocolo (AC4).

    Los de 32 bits también muestran el decimal con signo si el bit 31 está prendido
    (`imm = 0xfffffffc` → `4294967292 (-4)`): un inmediato o un dato negativo se reconoce así.
    """
    filas = []
    for f in fields(latch):
        valor = int(getattr(latch, f.name))
        if f.name in _DE_32_BITS:
            hexa = f"0x{valor:08x}"
            decimal = f"{valor} ({valor - (1 << 32)})" if valor >> 31 else str(valor)
        else:
            hexa, decimal = f"0x{valor:x}", str(valor)
        filas.append((f.name, hexa, decimal))
    return filas


# --- "Qué pasó en este ciclo" (debajo de las etapas) ----------------------------------------

_JAL = 0b1101111
_MASCARA = 0xFFFFFFFF


def destino_salto(snapshot: Snapshot) -> int | None:
    """A dónde salta lo que provoca el flush de este ciclo; None si no hay salto o es jalr.

    - flush de ID/EX: un branch tomado (o `jalr`) en EX: `pc + imm` de ID/EX.
    - solo flush de IF/ID: un `jal` en ID: `pc + imm` de IF/ID.
    `jalr` va a `(rs1 + imm) & ~1` con rs1 quizás adelantado: no se puede deducir del latch.
    """
    r, idex, ifid = snapshot.riesgos, snapshot.id_ex, snapshot.if_id
    if r.flush_id_ex:
        return None if idex.jalr else (idex.pc + idex.imm) & _MASCARA
    if r.flush_if_id and ifid.instr & 0x7F == _JAL:
        return (ifid.pc + decode_j(ifid.instr).imm) & _MASCARA
    return None


def senales(snapshot: Snapshot) -> list[tuple[str, bool]]:
    """Las salidas de la Hazard Unit y la Forwarding Unit, como chips: (texto, activa)."""
    r = snapshot.riesgos
    return [
        (f"stall = {int(r.stall)}", r.stall),
        (f"flush_if_id = {int(r.flush_if_id)}", r.flush_if_id),
        (f"flush_id_ex = {int(r.flush_id_ex)}", r.flush_id_ex),
        (f"fwd_a = {r.fwd_a:02b}", r.fwd_a != 0),
        (f"fwd_b = {r.fwd_b:02b}", r.fwd_b != 0),
    ]


def explicar(snapshot: Snapshot, columnas: list[Columna]) -> list[str]:
    """Una oración por cosa que pasó en el ciclo, armada con las señales del snapshot."""
    c = {col.etapa: col for col in columnas}
    r = snapshot.riesgos
    frases = []
    if snapshot.motivo is not None:
        frases.append(f"Terminó: {snapshot.motivo.name}. El núcleo está congelado.")
    if r.stall:
        frases.append(
            f"Load-use: «{c['EX'].texto}» está en EX y todavía no leyó la memoria, y "
            f"«{c['ID'].texto}» en ID necesita ese dato. IF e ID se congelan (el ciclo que "
            "viene muestran lo mismo) y entra una burbuja a EX."
        )
    destino = destino_salto(snapshot)
    hacia = f" → 0x{destino:x}" if destino is not None else ""
    if r.flush_id_ex:
        frases.append(
            f"«{c['EX'].texto}» en EX salta (tomado{hacia}): lo que entró detrás, "
            f"«{c['ID'].texto}» en ID y «{c['IF'].texto}» en IF, se descarta (flush)."
        )
    elif r.flush_if_id:
        frases.append(
            f"«{c['ID'].texto}» salta desde ID{hacia}: se descarta «{c['IF'].texto}», "
            "que se buscó de más (flush de IF/ID)."
        )
    for operando, fwd, campo in (("A", r.fwd_a, "rs1_data"), ("B", r.fwd_b, "rs2_data")):
        if fwd in _FUENTE_FWD:
            etapa, latch = _FUENTE_FWD[fwd]
            frases.append(
                f"Forwarding {operando}: EX toma el operando de {latch} («{c[etapa].texto}», "
                f"que todavía no escribió el registro). El {campo} de ID/EX es un valor viejo."
            )
    if not frases:
        frases.append("Sin riesgos: cada instrucción avanza una etapa.")
    return frases
