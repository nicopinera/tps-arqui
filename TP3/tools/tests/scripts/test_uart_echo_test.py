"""Lógica de comparación de `uart_echo_test.py` con un puerto falso, sin placa (US-401)."""

from scripts.uart_echo_test import probar_eco


class _PuertoEco:
    """Devuelve lo escrito; `perder` y `cambiar` simulan una placa con fallas."""

    def __init__(self, perder: int = 0, cambiar: int = 0) -> None:
        self._pendiente = b""
        self._perder = perder
        self._cambiar = cambiar

    def write(self, datos: bytes, /) -> int:
        if self._cambiar:
            datos = bytes([datos[0] ^ 0xFF]) + datos[1:]
            self._cambiar -= 1
        if self._perder:
            datos = datos[:-1]
            self._perder -= 1
        self._pendiente += datos
        return len(datos)

    def read(self, cantidad: int = 1, /) -> bytes:
        leido, self._pendiente = self._pendiente[:cantidad], self._pendiente[cantidad:]
        return leido


def test_eco_perfecto_no_tiene_errores() -> None:
    assert probar_eco(_PuertoEco(), bytes(range(256)) * 4) == 0


def test_byte_distinto_cuenta_un_error() -> None:
    assert probar_eco(_PuertoEco(cambiar=1), bytes(100)) == 1


def test_byte_perdido_cuenta_un_error() -> None:
    assert probar_eco(_PuertoEco(perder=2), bytes(100)) == 2


def test_ultimo_bloque_incompleto() -> None:
    assert probar_eco(_PuertoEco(), bytes(37), bloque=16) == 0
