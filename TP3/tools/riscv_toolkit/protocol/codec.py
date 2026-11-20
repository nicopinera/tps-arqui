"""Codec del protocolo con la Debug Unit (US-409, docs/protocolo.md §4 y §6).

- PC → FPGA: `encode_cmd`, `encode_load`, `encode_dump_mem` arman los bytes de cada comando.
- FPGA → PC: `FrameReader` junta los bytes que llegan y devuelve tramas `Trama` validadas.
- `encode_trama` arma una trama FPGA → PC (la usan `FakeTransport` y los tests).

El codec no decide si un comando vale en el estado actual ni si un rango de `DUMP_MEM` entra en
la DMEM: eso lo responde la Debug Unit con un `NACK` (R-DU-1). Solo rechaza lo que no se puede
representar en los campos, o lo que mandarlo destruiría estado (un `LOAD` mal formado borra la
IMEM).
"""

import time
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from functools import reduce
from operator import xor

from riscv_toolkit.protocol.comandos import (
    DMEM_DEPTH,
    IMEM_DEPTH,
    SNAP_PALABRA_USADA,
    SNAPSHOT_FIJO,
    SYNC,
    Comando,
    TipoTrama,
)
from riscv_toolkit.protocol.transport import Transport

_BYTES_PALABRA = 4
_BYTES_CAMPO = 2  # N de LOAD, dirección y n de DUMP_MEM, longitud de trama
_MAX_PALABRA = 0xFFFFFFFF
_MAX_CAMPO = 0xFFFF
_CABECERA = 4  # A5 + tipo + longitud (2 B)
_SOBRE = _CABECERA + 1  # cabecera + checksum: lo que una trama tiene además del payload
_MEM_DATA_FIJO = 4  # dirección (2 B) + n (2 B)

# Comandos que llevan argumentos: tienen su propio encode_*.
_CON_ARGUMENTOS = {Comando.LOAD, Comando.DUMP_MEM}


# --- Errores de recepción ------------------------------------------------------------------


class ErrorTrama(Exception):  # noqa: N818
    """Llegó algo que no es una trama válida. Ya se descartó: se puede seguir leyendo."""


class ErrorTipo(ErrorTrama):
    """El byte `tipo` no es ninguno de `TipoTrama`."""


class ErrorLongitud(ErrorTrama):
    """La longitud no es posible para el tipo (un ACK con payload, un snapshot de 222 B…)."""


class ErrorChecksum(ErrorTrama):
    """El XOR de tipo + longitud + payload no coincide con el último byte."""


class ErrorTramaTruncada(ErrorTrama):
    """La trama empezó pero se cortó: pasó el timeout sin que llegaran los bytes que faltaban."""


class ErrorPayload(ErrorTrama):
    """La trama está bien formada pero su contenido no (un estado o motivo que no existe)."""


# --- PC → FPGA -----------------------------------------------------------------------------


def checksum(datos: Iterable[int]) -> int:
    """XOR de todos los bytes (ADR-003). Lo usan `LOAD` y la validación de tramas."""
    return reduce(xor, datos, 0)


def encode_cmd(cmd: Comando) -> bytes:
    """Comando sin argumentos: un solo byte (`Comando.STEP` → `b"S"`)."""
    if cmd in _CON_ARGUMENTOS:
        raise ValueError(f"{cmd.name} lleva argumentos: usar encode_{cmd.name.lower()}")
    return bytes([cmd])


def encode_load(palabras: Sequence[int]) -> bytes:
    """`4C | N (2 B LE) | N palabras (4 B LE) | XOR de los 2 + 4N bytes` (protocolo §4)."""
    if not 1 <= len(palabras) <= IMEM_DEPTH:
        raise ValueError(f"LOAD lleva de 1 a {IMEM_DEPTH} palabras, no {len(palabras)}")
    for i, palabra in enumerate(palabras):
        if not 0 <= palabra <= _MAX_PALABRA:
            raise ValueError(f"la palabra {i} no entra en 32 bits: {palabra:#x}")

    cuerpo = len(palabras).to_bytes(_BYTES_CAMPO, "little") + b"".join(
        p.to_bytes(_BYTES_PALABRA, "little") for p in palabras
    )
    return bytes([Comando.LOAD]) + cuerpo + bytes([checksum(cuerpo)])


def encode_dump_mem(addr: int, n: int) -> bytes:
    """`4D | dirección en bytes (2 B LE) | n palabras (2 B LE)` (protocolo §4).

    No valida alineación ni rango: un pedido fuera de la DMEM se manda igual y la Debug Unit
    responde `NACK(ERR_RANGO)`, así la PC no duplica (y no puede contradecir) la regla del hardware.
    """
    for nombre, valor in (("dirección", addr), ("n", n)):
        if not 0 <= valor <= _MAX_CAMPO:
            raise ValueError(f"{nombre} no entra en 2 bytes: {valor}")
    return (
        bytes([Comando.DUMP_MEM])
        + addr.to_bytes(_BYTES_CAMPO, "little")
        + n.to_bytes(_BYTES_CAMPO, "little")
    )


# --- FPGA → PC -----------------------------------------------------------------------------


@dataclass(frozen=True)
class Trama:
    """Trama FPGA → PC ya validada: el tipo y el payload, sin el sobre (A5, longitud, XOR)."""

    tipo: TipoTrama
    payload: bytes


def encode_trama(tipo: TipoTrama, payload: bytes) -> bytes:
    """`A5 | tipo | longitud LE | payload | XOR(tipo, longitud, payload)` (protocolo §6)."""
    cuerpo = bytes([tipo]) + len(payload).to_bytes(_BYTES_CAMPO, "little") + payload
    return bytes([SYNC]) + cuerpo + bytes([checksum(cuerpo)])


def longitud_valida(tipo: TipoTrama, longitud: int) -> bool:
    """Si `longitud` es posible para `tipo` (protocolo §6.1)."""
    match tipo:
        case TipoTrama.ACK:
            return longitud == 0
        case TipoTrama.NACK | TipoTrama.PING_INFO:
            return longitud == 1
        case TipoTrama.SNAPSHOT:
            k, resto = divmod(longitud - SNAPSHOT_FIJO, SNAP_PALABRA_USADA)
            return resto == 0 and 0 <= k <= DMEM_DEPTH
        case TipoTrama.MEM_DATA:
            n, resto = divmod(longitud - _MEM_DATA_FIJO, _BYTES_PALABRA)
            return resto == 0 and 1 <= n <= DMEM_DEPTH


class FrameReader:
    """Arma tramas a partir de bytes que llegan en pedazos de cualquier tamaño.

    La UART entrega un flujo de bytes sin separaciones: una trama puede llegar en varios `read`
    y un `read` puede traer el final de una y el principio de otra. El lector las va juntando en
    un buffer y corta cada trama cuando la tiene completa.

    Ante una trama inválida lanza un `ErrorTrama` **después** de descartarla, así la próxima
    llamada sigue con la siguiente (resincronización, protocolo §7.4):

    - bytes antes de un `A5`: se descartan en silencio;
    - tipo o longitud imposibles: se descarta solo el `A5` y se busca el siguiente, porque la
      longitud no es confiable y saltear esa cantidad podría comerse la trama siguiente;
    - checksum malo: se descarta la trama entera (la cabecera era plausible, y un `A5` dentro
      del payload haría arrancar una trama falsa).
    """

    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, datos: bytes) -> None:
        """Agrega bytes recibidos al buffer."""
        self._buffer += datos

    def pendientes(self) -> int:
        """Bytes en el buffer que todavía no formaron una trama."""
        return len(self._buffer)

    def pop(self) -> Trama | None:
        """La próxima trama completa, o None si faltan bytes. `ErrorTrama` si era inválida."""
        inicio = self._buffer.find(SYNC)
        if inicio < 0:
            self._buffer.clear()  # nada de esto puede ser una trama
            return None
        del self._buffer[:inicio]
        if len(self._buffer) < _CABECERA:
            return None

        tipo_byte = self._buffer[1]
        longitud = int.from_bytes(self._buffer[2:_CABECERA], "little")
        if tipo_byte not in TipoTrama:
            del self._buffer[0]
            raise ErrorTipo(f"tipo de trama desconocido: {tipo_byte:#04x}")
        tipo = TipoTrama(tipo_byte)
        if not longitud_valida(tipo, longitud):
            del self._buffer[0]
            raise ErrorLongitud(f"{tipo.name} no puede tener {longitud} bytes de payload")

        total = _SOBRE + longitud
        if len(self._buffer) < total:
            return None
        trama = bytes(self._buffer[:total])
        del self._buffer[:total]
        if checksum(trama[1:]) != 0:  # tipo + longitud + payload + XOR = 0 si coincide
            raise ErrorChecksum(f"checksum de {tipo.name} inválido: llegó {trama[-1]:#04x}")
        return Trama(tipo, trama[_CABECERA:-1])

    def leer(self, transport: Transport, timeout: float | None) -> Trama:
        """Lee de `transport` hasta tener una trama completa y la devuelve.

        `timeout` es el tiempo máximo total (None = sin límite). Si no llega nada lanza
        `TimeoutError`; si la trama empezó y no terminó, `ErrorTramaTruncada` (y la descarta).
        """
        limite = None if timeout is None else time.monotonic() + timeout
        while (trama := self.pop()) is None:
            restante = None if limite is None else max(limite - time.monotonic(), 0.0)
            datos = transport.read(self._faltan(), restante)  # restante 0: solo lo que ya llegó
            if not datos:
                if self._buffer:
                    descartados = len(self._buffer)
                    self._buffer.clear()
                    raise ErrorTramaTruncada(f"trama cortada: llegaron {descartados} bytes")
                raise TimeoutError("la Debug Unit no respondió")
            self.feed(datos)
        return trama

    def _faltan(self) -> int:
        """Cuántos bytes pedir para completar la cabecera o la trama (al menos 1)."""
        if len(self._buffer) < _CABECERA:
            return _CABECERA - len(self._buffer)
        longitud = int.from_bytes(self._buffer[2:_CABECERA], "little")
        return max(_SOBRE + longitud - len(self._buffer), 1)
