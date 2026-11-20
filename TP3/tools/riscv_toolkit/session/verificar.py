"""Comparar el resultado de la placa con el golden model (US-411, US-505).

Lo usan `scripts/verify_board.py` (reporte de texto) y el botón Verificar de la GUI (tabla).
Se compara el estado arquitectónico final: motivo de terminación, registros y memoria usada.
El PC no: en la placa queda congelado unos ciclos después del HALT, y en el golden model en el
HALT.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from riscv_toolkit.iss.golden_model import EstadoArquitectonico, GoldenModel
from riscv_toolkit.iss.golden_model import Motivo as MotivoISS
from riscv_toolkit.protocol.comandos import Motivo
from riscv_toolkit.protocol.snapshot import Snapshot

MAX_INSTR = 100_000  # como rvsim: más es un loop infinito
_MOTIVOS = {MotivoISS.HALTED: Motivo.HALTED, MotivoISS.ILLEGAL: Motivo.ILLEGAL}


@dataclass(frozen=True)
class Diferencia:
    """Una fila del panel Verificar: qué difiere, lo que dio la placa y lo esperado."""

    que: str  # "motivo", "x1", "[0x100]"
    obtenido: str
    esperado: str
    ok: bool = False  # True: una fila de `comparacion` que coincide

    def __str__(self) -> str:
        """Como lo imprime `verify_board`: `x1 = 0x00000001 (esperado 0x00000090)`."""
        if self.que == "motivo":
            return f"motivo {self.obtenido} (esperado {self.esperado})"
        return f"{self.que} = {self.obtenido} (esperado {self.esperado})"


def esperado_de(palabras: Sequence[int]) -> EstadoArquitectonico | None:
    """Corre el programa en el golden model. None si no termina (loop infinito)."""
    modelo = GoldenModel(list(palabras))
    if modelo.run(MAX_INSTR) is MotivoISS.TIMEOUT:
        return None
    return modelo.estado_final()


def comparacion(snap: Snapshot, esperado: EstadoArquitectonico) -> list[Diferencia]:
    """Todo lo que se compara, coincida o no: el motivo, los registros que no valen 0 en
    alguno de los dos lados (los que valen 0 en los dos se ocultan) y la memoria usada."""
    motivo = _MOTIVOS.get(esperado.motivo)
    filas = [
        Diferencia(
            "motivo", nombre_motivo(snap.motivo), nombre_motivo(motivo), snap.motivo is motivo
        )
    ]
    for n, (real, ideal) in enumerate(zip(snap.regs, esperado.regs, strict=True)):
        if real or ideal:
            filas.append(Diferencia(f"x{n}", f"0x{real:08x}", f"0x{ideal:08x}", real == ideal))
    # La memoria usada se compara con claves: una palabra escrita de más o de menos es un bug
    # del registro de palabras usadas, aunque valga 0.
    for d in sorted(snap.mem_usada.keys() | esperado.mem_usada.keys()):
        real_m, ideal_m = snap.mem_usada.get(d), esperado.mem_usada.get(d)
        filas.append(
            Diferencia(f"[0x{d:03x}]", _palabra(real_m), _palabra(ideal_m), real_m == ideal_m)
        )
    return filas


def diferencias(snap: Snapshot, esperado: EstadoArquitectonico) -> list[Diferencia]:
    """Diferencias entre el snapshot final de la placa y el golden model (vacía si coinciden)."""
    return [d for d in comparacion(snap, esperado) if not d.ok]


def comparar(snap: Snapshot, esperado: EstadoArquitectonico) -> list[str]:
    """`diferencias` como texto, para el reporte de `verify_board`."""
    return [str(d) for d in diferencias(snap, esperado)]


def nombre_motivo(motivo: Motivo | None) -> str:
    return motivo.name if motivo is not None else "ninguno"


def _palabra(valor: int | None) -> str:
    return "no escrita" if valor is None else f"0x{valor:08x}"
