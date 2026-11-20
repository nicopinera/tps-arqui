"""Transporte por el puerto serie real de la Basys 3 (US-409, ADR-002).

Es el único módulo del paquete que importa `serial` (AC5): el resto del software usa la
interfaz `Transport` y no se entera de si habla con la placa o con `FakeTransport`.
"""

import serial
from serial.tools import list_ports

BAUD = 19200  # ADR-002: 8E1 a 19200 bps
# Conversor USB de la Basys 3: FTDI FT2232HQ. Expone dos interfaces: la A es el JTAG (la usa
# Vivado) y la B es la UART.
FTDI_VID = 0x0403
FT2232_PID = 0x6010


class ErrorPuerto(Exception):  # noqa: N818
    """No se encontró la placa, o hay varias y hay que elegir el puerto a mano."""


def detectar_puerto() -> str:
    """Nombre del puerto de la UART de la Basys 3 (`COM5`, `/dev/ttyUSB1`, …).

    Busca el VID/PID del FT2232. En Linux aparecen las dos interfaces (`ttyUSB0` = JTAG,
    `ttyUSB1` = UART) y se toma la B; en Windows el driver de Vivado se queda con la A y queda
    un solo COM.
    """
    candidatos = sorted(
        p.device for p in list_ports.comports() if (p.vid, p.pid) == (FTDI_VID, FT2232_PID)
    )
    # shortcut: "la última interfaz es la UART" vale con una sola placa; con dos, --port.
    if not candidatos:
        raise ErrorPuerto("no se encontró la Basys 3 (FTDI 0403:6010): ¿está conectada?")
    return candidatos[-1]


class SerialTransport:
    """`Transport` sobre `pyserial`, configurado como la UART de la Debug Unit (8E1, 19200)."""

    simulado = False

    def __init__(self, puerto: str | None = None) -> None:
        """Abre `puerto`, o el de la Basys 3 si es None. `ErrorPuerto` si no se puede abrir."""
        nombre = puerto if puerto is not None else detectar_puerto()
        try:
            self._serie = serial.Serial(
                nombre,
                baudrate=BAUD,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_EVEN,
                stopbits=serial.STOPBITS_ONE,
                timeout=None,
            )
        except serial.SerialException as error:
            raise ErrorPuerto(f"{nombre}: {error}") from error
        self._serie.reset_input_buffer()  # bytes viejos de una sesión anterior

    def write(self, datos: bytes) -> None:
        self._serie.write(datos)
        # Espera a que salgan: un LOAD de 256 palabras tarda ~0,6 s, y el timeout de la
        # respuesta tiene que empezar a contar después, no mientras todavía se está mandando.
        self._serie.flush()

    def read(self, n: int, timeout: float | None) -> bytes:
        self._serie.timeout = timeout
        return bytes(self._serie.read(n))

    def close(self) -> None:
        self._serie.close()
