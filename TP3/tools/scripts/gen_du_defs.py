"""Genera `hw/rtl/debug/du_defs.vh` desde `riscv_toolkit/protocol/comandos.py` (US-104).

Uso (desde TP3/tools/):  uv run python -m scripts.gen_du_defs
"""

from enum import IntEnum
from pathlib import Path

from riscv_toolkit.isa.instrucciones import HALT_OPCODE, HALT_WORD
from riscv_toolkit.protocol import comandos as c
from riscv_toolkit.protocol.comandos import Comando, ErrorNack, EstadoDU, Motivo, TipoTrama

RUTA_VH = Path(__file__).resolve().parents[2] / "hw" / "rtl" / "debug" / "du_defs.vh"

GRUPOS: list[tuple[type[IntEnum], str, int]] = [
    (Comando, "CMD", 8),
    (ErrorNack, "ERR", 8),
    (TipoTrama, "TIPO", 8),
    (EstadoDU, "ESTADO", 4),
    (Motivo, "MOTIVO", 4),
]

# (nombre, valor, ancho). Ancho None = tamaño o cantidad: va en decimal, para usar como parámetro.
# SIGNATURE_ADDR no va: solo la usan los programas de prueba.
CONSTANTES: list[tuple[str, int, int | None]] = [
    ("PROTO_VERSION", c.PROTO_VERSION, 8),
    ("SYNC", c.SYNC, 8),
    ("HALT_WORD", HALT_WORD, 32),
    ("HALT_OPCODE", HALT_OPCODE, 7),
    ("IMEM_DEPTH", c.IMEM_DEPTH, None),
    ("DMEM_DEPTH", c.DMEM_DEPTH, None),
    ("RX_TIMEOUT_MS", c.RX_TIMEOUT_MS, None),
    ("SNAPSHOT_FIJO", c.SNAPSHOT_FIJO, None),
    ("SNAP_PALABRA_USADA", c.SNAP_PALABRA_USADA, None),
]


def _literal(valor: int, ancho: int | None) -> str:
    """Literal de Verilog: `8'h4C` con ancho, `256` sin ancho."""
    if ancho is None:
        return str(valor)
    return f"{ancho}'h{valor:0{(ancho + 3) // 4}X}"


def generar_vh() -> str:
    """Devuelve el contenido de `du_defs.vh`, sin escribir nada en disco."""
    lineas: list[str] = []
    lineas.append(
        "// GENERADO por tools/scripts/gen_du_defs.py desde riscv_toolkit/protocol/comandos.py."
    )
    lineas.append("// NO EDITAR A MANO: cambiar comandos.py y regenerar.")
    lineas.append("")
    lineas.append("`ifndef DU_DEFS_VH")
    lineas.append("`define DU_DEFS_VH")
    lineas.append("")

    for enum, prefijo, ancho in GRUPOS:
        lineas.append(f"// {enum.__name__}")
        for miembro in enum:
            lineas.append(f"`define DU_{prefijo}_{miembro.name} {_literal(miembro, ancho)}")
        lineas.append("")

    lineas.append("// Constantes")
    for nombre, valor, ancho_constante in CONSTANTES:
        lineas.append(f"`define DU_{nombre} {_literal(valor, ancho_constante)}")
    lineas.append("")

    lineas.append("`endif")
    return "\n".join(lineas) + "\n"


def main() -> None:
    # newline="\n": el .vh sale igual en Windows y en el CI (Linux).
    RUTA_VH.write_text(generar_vh(), encoding="ascii", newline="\n")
    print(f"Generado {RUTA_VH}")


if __name__ == "__main__":
    main()
