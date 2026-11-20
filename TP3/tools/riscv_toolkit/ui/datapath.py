"""Vista Datapath: el valor de cada señal del diagrama en un ciclo y qué resaltar (sin Flet).

El diagrama (`docs/diagramas/datapath_pipeline.drawio`) nombra cada cable con el campo y la
etapa: `rs1_dataE` es el `rs1_data` del latch que alimenta EX (ID/EX), `alu_resultM` el
`alu_result` de EX/MEM. Con esa regla:
- **medido**: el campo existe en el latch del snapshot (lo que mandó la placa, o el fake);
- **calculado**: lo combinacional (`srcA`, `alu_resultE`, `rs1D`, `StallF`, …) no viaja en el
  snapshot; lo recalcula `ModeloPipeline` desde el estado del snapshot. Con la placa es lo
  que el RTL *debería* tener, no lo que tiene: por eso la vista lo muestra distinto.

Las posiciones salen de `assets/datapath/datapath.json`, que arma `scripts/gen_datapath.py`.
"""

import json
import re
from collections.abc import Iterable
from dataclasses import dataclass, fields
from typing import Any

from riscv_toolkit.iss.pipeline_model import ModeloPipeline
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.ui.tema import ASSETS

MAPA = ASSETS / "datapath" / "datapath.json"
_LATCH = {"D": "if_id", "E": "id_ex", "M": "ex_mem", "W": "mem_wb"}  # sufijo → latch de entrada
_UN_BIT = re.compile(
    r"(reg_write|mem_read|mem_write|alu_src|branch|jump|jalr|halt|illegal|valid|uses_rs[12]"
    r"|funct7_b5)[DFEMW]?|eq|redirect_ex|(Stall|Flush)[A-Z]"
)
_BITS = {"fwd_a": 2, "fwd_b": 2, "pc_sel": 2, "imm_type": 3, "op": 7, "funct7": 7}
_BITS_PREFIJO = {"result_src": 2, "alu_op": 2, "funct3": 3}
_REGISTRO = re.compile(r"(rs1|rs2|rd)[DEMW]")
_ALIAS = {"uses_rs1D": "uses_rs1", "uses_rs2D": "uses_rs2"}  # el mismo cable, dos rótulos

# Cada mux del diagrama (id de la celda) → la señal que lo maneja y cuándo cuenta.
MUX_SELECTOR = {
    "tp3-207": ("fwd_a", "validE"),
    "tp3-208": ("fwd_b", "validE"),
    "tp3-209": ("alu_srcE", "validE"),
    "tp3-216": ("jalrE", "validE"),
    "tp3-26": ("pc_sel", None),
    "tp3-344": ("result_srcW", "validW"),
}


@dataclass(frozen=True)
class Valor:
    texto: str
    medido: bool  # False: lo calculó el modelo, no viene en el snapshot


@dataclass(frozen=True)
class Resaltes:
    """Qué marcar en el dibujo. Las claves de color son las de `tema.RIESGO` (None: neutro)."""

    bloques: dict[str, str]  # "PC", "IF/ID", "ID/EX" → "st" (stall) o "fl" (flush)
    muxes: dict[str, tuple[str, str | None]]  # id del mux → (entrada elegida, color)


def cargar_mapa() -> dict[str, Any]:
    return json.loads(MAPA.read_text(encoding="utf-8"))  # type: ignore[no-any-return]


def nombre_de(etiqueta: str) -> str:
    """`"result_srcD 1:0"` → `"result_srcD"`: la primera palabra del rótulo."""
    return etiqueta.split()[0] if etiqueta.split() else ""


def formatear(nombre: str, valor: int) -> str:
    """Como se lee en el dibujo: bits sueltos en 0/1, selectores en binario, registros como
    `x5`, la instrucción con 8 dígitos y el resto (datos de 32 bits) en hex corto."""
    base = nombre[:-1] if nombre[-1:] in "DFEMW" else nombre
    bits = _BITS.get(nombre) or _BITS_PREFIJO.get(base)
    if _UN_BIT.fullmatch(nombre):
        return str(int(valor))
    if bits:
        return f"{valor:0{bits}b}"
    if _REGISTRO.fullmatch(nombre):
        return f"x{valor}"
    if base == "instr":
        return f"{valor:08x}"
    return f"0x{valor:x}"


def _medido(nombre: str, snap: Snapshot) -> int | None:
    if nombre in ("fwd_a", "fwd_b"):
        return int(getattr(snap.riesgos, nombre))
    if nombre in ("pcF", "o_pc"):
        return snap.pc
    latch = _LATCH.get(nombre[-1:])
    if latch is None:
        return None
    datos = getattr(snap, latch)
    campo = nombre[:-1]
    if campo not in {f.name for f in fields(datos)}:
        return None
    return int(getattr(datos, campo))


def valores_datapath(
    snap: Snapshot, imem: list[int] | None, nombres: Iterable[str]
) -> dict[str, Valor]:
    """El valor de cada nombre del diagrama que se sabe en este ciclo.

    Sin el programa (`imem` None, una sesión reabierta sin el .asm) solo los medidos: sin la
    IMEM el modelo no sabe qué busca IF.
    """
    cables = ModeloPipeline.desde_snapshot(snap, imem).cables() if imem is not None else {}
    for alias, cable in _ALIAS.items():
        if cable in cables:
            cables[alias] = cables[cable]
    valores = {}
    for nombre in nombres:
        medido = _medido(nombre, snap)
        if medido is not None:
            valores[nombre] = Valor(formatear(nombre, medido), True)
        elif nombre in cables:
            valores[nombre] = Valor(formatear(nombre, cables[nombre]), False)
    return valores


def resaltes(valores: dict[str, Valor]) -> Resaltes:
    """Los latches que se congelan o se vacían y la entrada que elige cada mux."""

    def uno(nombre: str) -> bool:
        return nombre in valores and valores[nombre].texto == "1"

    bloques = {}
    if uno("StallF"):
        bloques["PC"] = "st"
    if uno("StallD"):  # load-use: IF/ID repite y a ID/EX entra la burbuja del stall
        bloques["IF/ID"] = bloques["ID/EX"] = "st"
    else:
        if uno("FlushD"):
            bloques["IF/ID"] = "fl"
        if uno("FlushE"):
            bloques["ID/EX"] = "fl"
    muxes: dict[str, tuple[str, str | None]] = {}
    for mux, (selector, valido) in MUX_SELECTOR.items():
        if selector not in valores or (valido is not None and not uno(valido)):
            continue
        opcion = valores[selector].texto
        color = None
        if selector == "fwd_a" and opcion != "00":
            color = "fa"
        elif selector == "fwd_b" and opcion != "00":
            color = "fb"
        elif selector == "pc_sel" and opcion != "00":
            color = "fl"
        muxes[mux] = (opcion, color)
    return Resaltes(bloques, muxes)
