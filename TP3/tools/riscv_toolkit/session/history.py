"""Historial de snapshots de una sesión, con un cursor (US-410).

Como el atrás/adelante de un navegador: la sesión agrega cada snapshot que recibe y el cursor
salta al último; la GUI mueve el cursor para volver a ver ciclos anteriores sin pedirle nada a
la placa.
"""

from riscv_toolkit.protocol.snapshot import Snapshot


class SnapshotHistory:
    """Lista de snapshots en el orden en que llegaron y el índice del que se está mirando."""

    def __init__(self) -> None:
        self._snapshots: list[Snapshot] = []
        self._indice = -1  # -1 = vacío

    def __len__(self) -> int:
        return len(self._snapshots)

    @property
    def indice(self) -> int:
        """Posición del cursor (-1 si el historial está vacío)."""
        return self._indice

    @property
    def actual(self) -> Snapshot | None:
        """El snapshot bajo el cursor, o None si no hay ninguno."""
        return self._snapshots[self._indice] if self._snapshots else None

    def agregar(self, snapshot: Snapshot) -> None:
        """Agrega al final y mueve el cursor ahí (lo último que pasó es lo que se muestra)."""
        self._snapshots.append(snapshot)
        self._indice = len(self._snapshots) - 1

    def limpiar(self) -> None:
        """Vacía el historial: después de LOAD o RESET los snapshots viejos son de otra corrida."""
        self._snapshots.clear()
        self._indice = -1

    def ir_a(self, indice: int) -> Snapshot:
        """Mueve el cursor a `indice` (acepta negativos). `IndexError` si no existe."""
        snapshot = self._snapshots[indice]
        self._indice = indice % len(self._snapshots)
        return snapshot

    def anterior(self) -> Snapshot | None:
        """Retrocede uno. En el primero (o vacío) no se mueve y devuelve None."""
        if self._indice <= 0:
            return None
        return self.ir_a(self._indice - 1)

    def siguiente(self) -> Snapshot | None:
        """Avanza uno. En el último (o vacío) no se mueve y devuelve None."""
        if self._indice >= len(self._snapshots) - 1:
            return None
        return self.ir_a(self._indice + 1)
