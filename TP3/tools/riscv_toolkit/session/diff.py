"""Qué cambió entre dos snapshots (US-410): lo usa la GUI para resaltar y `verify_board --step`.

Solo el estado arquitectónico (PC, registros y memoria). Los latches cambian en todos los
ciclos, así que marcarlos no dice nada.
"""

from dataclasses import dataclass

from riscv_toolkit.protocol.snapshot import Snapshot

Cambio = tuple[int, int]  # (antes, después)


@dataclass(frozen=True)
class CambiosEstado:
    """Lo que cambió de `a` a `b`. Cada diccionario tiene solo las posiciones distintas."""

    pc: Cambio | None  # None si el PC es el mismo
    regs: dict[int, Cambio]  # número de registro → (antes, después)
    memoria: dict[int, Cambio]  # dirección en bytes → (antes, después)

    def __bool__(self) -> bool:
        """True si cambió algo: `if diff(a, b): ...`."""
        return self.pc is not None or bool(self.regs) or bool(self.memoria)


def diff(a: Snapshot, b: Snapshot) -> CambiosEstado:
    """Diferencias de estado entre `a` (antes) y `b` (después).

    Una palabra que no está en `mem_usada` vale 0: la DMEM arranca en 0 y el snapshot solo
    trae las escritas (ADR-008). Escribir un 0 donde no había nada no cuenta como cambio.
    """
    regs = {n: (x, y) for n, (x, y) in enumerate(zip(a.regs, b.regs, strict=True)) if x != y}
    memoria = {}
    for direccion in sorted(a.mem_usada.keys() | b.mem_usada.keys()):
        antes, despues = a.mem_usada.get(direccion, 0), b.mem_usada.get(direccion, 0)
        if antes != despues:
            memoria[direccion] = (antes, despues)
    pc = None if a.pc == b.pc else (a.pc, b.pc)
    return CambiosEstado(pc, regs, memoria)
