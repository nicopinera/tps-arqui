"""Prueba de eco de la UART en la placa (US-401, AC1).

Con el `top` de US-401 cargado (eco temporal), manda bytes aleatorios a 19200 bps 8E1 y
verifica que vuelvan iguales.

Uso (desde TP3/tools/):  uv run python -m scripts.uart_echo_test COM5
                         uv run python -m scripts.uart_echo_test /dev/ttyUSB1 --bytes 1000

Manda de a bloques y espera el eco de cada uno: la placa transmite un 0,15 % más lento de lo
que recibe (COUNT_MAX = 326), y sin pausas el TX del eco se atrasa hasta perder bytes.
Sale con 0 si todos los bytes volvieron bien y con 1 si no.
"""

import argparse
import random
import sys
from typing import Protocol

import serial

BAUD = 19200
_BLOQUE = 16  # atraso acumulado por bloque: 16 tramas x 0,15 % = 0,26 bits, no pierde bytes
_TIMEOUT_S = 1.0  # un bloque de 16 bytes tarda ~9 ms en ir y volver


class Puerto(Protocol):
    """Lo que el test usa de `serial.Serial` (permite probarlo con un puerto falso)."""

    def write(self, datos: bytes, /) -> int | None: ...
    def read(self, cantidad: int = 1, /) -> bytes: ...


def probar_eco(puerto: Puerto, datos: bytes, bloque: int = _BLOQUE) -> int:
    """Manda `datos` de a `bloque` bytes y devuelve cuántos no volvieron iguales."""
    errores = 0
    for inicio in range(0, len(datos), bloque):
        enviado = datos[inicio : inicio + bloque]
        puerto.write(enviado)
        recibido = puerto.read(len(enviado))
        # Un byte faltante (timeout o perdido) cuenta como error, igual que uno distinto
        errores += len(enviado) - len(recibido)
        errores += sum(a != b for a, b in zip(enviado, recibido, strict=False))
    return errores


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prueba de eco de la UART de la Basys 3")
    parser.add_argument("puerto", help="puerto serie de la placa (COM5, /dev/ttyUSB1, ...)")
    parser.add_argument("--bytes", type=int, default=1000, help="cantidad de bytes a mandar")
    parser.add_argument("--semilla", type=int, help="semilla para repetir la misma secuencia")
    args = parser.parse_args(argv)

    datos = random.Random(args.semilla).randbytes(args.bytes)  # noqa: S311 (no es criptografía)
    try:
        with serial.Serial(
            args.puerto,
            baudrate=BAUD,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_EVEN,
            stopbits=serial.STOPBITS_ONE,
            timeout=_TIMEOUT_S,
        ) as puerto:
            puerto.reset_input_buffer()
            errores = probar_eco(puerto, datos)
    except serial.SerialException as error:
        print(f"{args.puerto}: error: {error}", file=sys.stderr)
        return 1

    print(f"{args.bytes - errores} de {args.bytes} bytes volvieron bien")
    return 0 if errores == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
