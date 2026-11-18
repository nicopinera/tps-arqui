"""SerialTransport sin placa: configuración del puerto y detección (US-409, AC5 y AC6)."""

import ast
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest
import serial
from serial.tools import list_ports

from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import (
    BAUD,
    ErrorPuerto,
    SerialTransport,
    detectar_puerto,
)
from riscv_toolkit.protocol.transport import Transport

PAQUETE = Path(__file__).resolve().parents[2] / "riscv_toolkit"


class SerieFalsa:
    """Reemplaza a `serial.Serial`: guarda cómo se abrió y lo que se escribió."""

    def __init__(self, puerto: str, **config: Any) -> None:
        self.puerto, self.config = puerto, config
        self.timeout: float | None = config["timeout"]
        self.escrito, self.cerrado = b"", False
        self.por_leer = b"\xa5\x01\x00\x00\x01"

    def reset_input_buffer(self) -> None:
        pass

    def write(self, datos: bytes) -> int:
        self.escrito += datos
        return len(datos)

    def flush(self) -> None:
        pass

    def read(self, n: int) -> bytes:
        datos, self.por_leer = self.por_leer[:n], self.por_leer[n:]
        return datos

    def close(self) -> None:
        self.cerrado = True


@pytest.fixture
def serie(monkeypatch: pytest.MonkeyPatch) -> list[SerieFalsa]:
    abiertos: list[SerieFalsa] = []

    def abrir(puerto: str, **config: Any) -> SerieFalsa:
        abiertos.append(SerieFalsa(puerto, **config))
        return abiertos[-1]

    monkeypatch.setattr(serial, "Serial", abrir)
    return abiertos


def test_abre_a_19200_8e1(serie: list[SerieFalsa]) -> None:  # AC6
    SerialTransport("COM5")
    (abierto,) = serie
    assert abierto.puerto == "COM5"
    assert abierto.config["baudrate"] == BAUD == 19200
    assert abierto.config["bytesize"] == serial.EIGHTBITS
    assert abierto.config["parity"] == serial.PARITY_EVEN
    assert abierto.config["stopbits"] == serial.STOPBITS_ONE


def test_write_read_close(serie: list[SerieFalsa]) -> None:
    transporte = SerialTransport("COM5")
    transporte.write(b"?")
    assert transporte.read(5, timeout=0.5) == b"\xa5\x01\x00\x00\x01"
    assert serie[0].timeout == 0.5  # cada read fija su timeout
    transporte.close()
    assert serie[0].escrito == b"?"
    assert serie[0].cerrado


def test_puerto_que_no_abre(monkeypatch: pytest.MonkeyPatch) -> None:
    def falla(puerto: str, **config: Any) -> None:
        raise serial.SerialException("acceso denegado")

    monkeypatch.setattr(serial, "Serial", falla)
    with pytest.raises(ErrorPuerto, match="COM9"):
        SerialTransport("COM9")


def _puertos(monkeypatch: pytest.MonkeyPatch, *puertos: tuple[str, int, int]) -> None:
    lista = [SimpleNamespace(device=d, vid=v, pid=p) for d, v, p in puertos]
    monkeypatch.setattr(list_ports, "comports", lambda: lista)


def test_detecta_la_interfaz_uart_de_la_basys3(monkeypatch: pytest.MonkeyPatch) -> None:
    _puertos(
        monkeypatch,
        ("/dev/ttyUSB1", 0x0403, 0x6010),
        ("/dev/ttyACM0", 0x2341, 0x0043),  # otra placa: se ignora
        ("/dev/ttyUSB0", 0x0403, 0x6010),
    )
    assert detectar_puerto() == "/dev/ttyUSB1"


def test_sin_placa(monkeypatch: pytest.MonkeyPatch) -> None:
    _puertos(monkeypatch, ("COM3", 0x2341, 0x0043))
    with pytest.raises(ErrorPuerto, match="no se encontró"):
        detectar_puerto()


def test_sin_puerto_usa_el_detectado(
    serie: list[SerieFalsa], monkeypatch: pytest.MonkeyPatch
) -> None:
    _puertos(monkeypatch, ("COM7", 0x0403, 0x6010))
    SerialTransport()
    assert serie[0].puerto == "COM7"


# --- AC5: solo serial_transport.py importa serial ------------------------------------------


def _importa_serial(archivo: Path) -> bool:
    for nodo in ast.walk(ast.parse(archivo.read_text(encoding="utf-8"))):
        if isinstance(nodo, ast.Import) and any(
            a.name.split(".")[0] == "serial" for a in nodo.names
        ):
            return True
        if isinstance(nodo, ast.ImportFrom) and (nodo.module or "").split(".")[0] == "serial":
            return True
    return False


def test_solo_serial_transport_importa_serial() -> None:
    importan = {
        p.relative_to(PAQUETE).as_posix() for p in PAQUETE.rglob("*.py") if _importa_serial(p)
    }
    assert importan == {"protocol/serial_transport.py"}


def test_los_dos_transportes_cumplen_la_interfaz() -> None:
    # mypy verifica la firma; acá, que la asignación tipada compile y el flag sea el correcto.
    fake: Transport = FakeTransport()
    assert fake.simulado
    assert not SerialTransport.simulado
