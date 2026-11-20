"""Sesiones exportadas para el plan B de la defensa (US-605 AC2), sin placa.

Uso (desde TP3/tools/):  uv run python -m scripts.sesiones_defensa

Corre cada programa del guion (`docs/defensa/guion.md`) paso a paso en la placa simulada
(`FakeTransport`, el modelo del pipeline) y exporta la sesión a `docs/defensa/sesiones/`, en el
mismo formato que el botón Exportar de la GUI. Se abren con Archivo → Abrir sesión y se ven
igual que en vivo, ciclo a ciclo.

Las sesiones quedan marcadas como simuladas ("simulado": true). Cuando la placa esté
validada, conviene reemplazarlas por sesiones exportadas desde la GUI con la placa.
"""

from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.session.debug_session import DebugSession
from riscv_toolkit.session.export import exportar

TP3 = Path(__file__).resolve().parents[2]
SALIDA = TP3.parent / "docs" / "defensa" / "sesiones"
PROGRAMAS = (
    "riesgos/06_load_use_stall",
    "riesgos/08_branch_tomado_flush",
    "riesgos/12_load_use_y_branch",
    "demos/fibonacci",
    "demos/burbuja",
)
MAX_PASOS = 2000


def grabar(nombre: str, destino: Path) -> int:
    """Corre `asm/<nombre>.asm` paso a paso y exporta la sesión. Devuelve los ciclos."""
    fuente = (TP3 / "asm" / f"{nombre}.asm").read_text(encoding="utf-8")
    palabras = ensamblar(fuente).palabras
    with DebugSession(FakeTransport()) as sesion:
        sesion.conectar()
        sesion.load(palabras)
        snap = sesion.dump()  # el ciclo 0, antes del primer paso
        for _ in range(MAX_PASOS):
            snap = sesion.step()
            if snap.motivo is not None:
                break
        else:
            raise RuntimeError(f"{nombre}: no terminó en {MAX_PASOS} pasos")
        sesion.historial.ir_a(0)  # la sesión se abre en el primer ciclo
        exportar(destino, sesion.historial, palabras, fuente)
        return snap.ciclos


def main() -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre in PROGRAMAS:
        destino = SALIDA / f"{nombre.replace('/', '_')}.json"
        ciclos = grabar(nombre, destino)
        print(f"{destino.relative_to(TP3.parent)}: {ciclos} ciclos")


if __name__ == "__main__":
    main()
