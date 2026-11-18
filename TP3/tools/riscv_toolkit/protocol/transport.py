"""Interfaz de transporte: por dónde viajan los bytes del protocolo (US-409).

El codec, la sesión (US-410) y la GUI dependen solo de esta interfaz, no de `pyserial`: así se
puede cambiar la placa por `FakeTransport` (golden model) sin tocar nada más.
"""

from typing import Protocol


class Transport(Protocol):
    """Canal de bytes con la Debug Unit, en los dos sentidos.

    Es un `Protocol` (tipado estructural): una clase lo cumple si tiene estos miembros, sin
    heredar de él. mypy lo verifica igual que una herencia.
    """

    simulado: bool  # True si las respuestas no vienen del hardware (el snapshot lo informa)

    def write(self, datos: bytes) -> None:
        """Manda todos los bytes."""
        ...

    def read(self, n: int, timeout: float | None) -> bytes:
        """Hasta `n` bytes. Devuelve menos (o `b""`) si pasan `timeout` segundos sin que lleguen.

        `timeout = None` espera sin límite. Un resultado vacío siempre significa "no llegó nada".
        """
        ...

    def close(self) -> None:
        """Libera el canal. Llamarlo dos veces no es un error."""
        ...
