"""Codec: comandos → bytes, contra los ejemplos de docs/protocolo.md §8 (US-409, AC1)."""

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.salidas import a_bin
from riscv_toolkit.protocol.codec import (
    ErrorChecksum,
    ErrorLongitud,
    ErrorPayload,
    ErrorTipo,
    ErrorTrama,
    ErrorTramaTruncada,
    FrameReader,
    Trama,
    checksum,
    encode_cmd,
    encode_dump_mem,
    encode_load,
    encode_trama,
)
from riscv_toolkit.protocol.comandos import IMEM_DEPTH, Comando, ErrorNack, TipoTrama

# Programa de los ejemplos del protocolo (§8).
PROGRAMA = [0x00500093, 0x00102023, 0x0000000B]  # addi x1, x0, 5 · sw x1, 0(x0) · halt


# --- encode_cmd ----------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("cmd", "esperado"),
    [
        (Comando.RUN, "52"),
        (Comando.STEP, "53"),  # §8.5
        (Comando.DUMP, "44"),  # §8.6
        (Comando.RESET, "58"),  # §8.3
        (Comando.ABORT, "41"),  # §8.8
        (Comando.PING, "3F"),  # §8.4
    ],
)
def test_comando_sin_argumentos_es_un_byte(cmd: Comando, esperado: str) -> None:
    assert encode_cmd(cmd) == bytes.fromhex(esperado)


@pytest.mark.parametrize("cmd", [Comando.LOAD, Comando.DUMP_MEM])
def test_comando_con_argumentos_no_va_por_encode_cmd(cmd: Comando) -> None:
    with pytest.raises(ValueError, match="lleva argumentos"):
        encode_cmd(cmd)


# --- encode_load ---------------------------------------------------------------------------


def test_load_del_ejemplo() -> None:  # §8.2
    assert encode_load(PROGRAMA) == bytes.fromhex("4C 0300 93005000 23201000 0B000000 D8")


def test_load_de_una_imagen_ensamblada() -> None:
    imagen = ensamblar("addi x1, x0, 5\nsw x1, 0(x0)\nhalt\n")
    trama = encode_load(imagen.palabras)
    assert trama == encode_load(PROGRAMA)
    assert trama[3:-1] == a_bin(imagen)  # el payload es el mismo .bin del ensamblador


def test_load_checksum_cubre_n_y_palabras() -> None:
    trama = encode_load(PROGRAMA)
    assert checksum(trama[1:]) == 0  # XOR de N + palabras + checksum = 0


def test_load_de_la_imem_completa() -> None:
    trama = encode_load([0x0000000B] * IMEM_DEPTH)
    assert len(trama) == 1 + 2 + 4 * IMEM_DEPTH + 1
    assert trama[1:3] == IMEM_DEPTH.to_bytes(2, "little")


@pytest.mark.parametrize(
    ("palabras", "mensaje"),
    [
        ([], "de 1 a 256"),
        ([0] * (IMEM_DEPTH + 1), "de 1 a 256"),
        ([0x1_0000_0000], "no entra en 32 bits"),
        ([-1], "no entra en 32 bits"),
    ],
)
def test_load_rechaza_lo_que_no_entra(palabras: list[int], mensaje: str) -> None:
    with pytest.raises(ValueError, match=mensaje):
        encode_load(palabras)


# --- encode_dump_mem -----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("addr", "n", "esperado"),
    [
        (0x000, 2, "4D 0000 0200"),  # §8.9
        (0x3FC, 2, "4D FC03 0200"),  # §8.9: fuera de rango, pero se codifica (la DU responde NACK)
        (0x001, 1, "4D 0100 0100"),  # desalineada: también la rechaza la DU, no el codec
        (0xFFFF, 0xFFFF, "4D FFFF FFFF"),
    ],
)
def test_dump_mem(addr: int, n: int, esperado: str) -> None:
    assert encode_dump_mem(addr, n) == bytes.fromhex(esperado)


@pytest.mark.parametrize(("addr", "n"), [(0x10000, 1), (-4, 1), (0, 0x10000), (0, -1)])
def test_dump_mem_rechaza_lo_que_no_entra_en_2_bytes(addr: int, n: int) -> None:
    with pytest.raises(ValueError, match="no entra en 2 bytes"):
        encode_dump_mem(addr, n)


# --- checksum ------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("datos", "esperado"),
    [
        ("", 0x00),
        ("01 00 00", 0x01),  # ACK: tipo + longitud (§8.1)
        ("02 01 00 05", 0x06),  # NACK(ERR_RANGO) (§8.1)
    ],
)
def test_checksum(datos: str, esperado: int) -> None:
    assert checksum(bytes.fromhex(datos)) == esperado


# --- FPGA → PC: encode_trama y FrameReader (AC1, AC3) --------------------------------------

ACK = bytes.fromhex("A5 01 00 00 01")
NACK_RANGO = bytes.fromhex("A5 02 01 00 05 06")


class TransportGuionado:
    """Transporte de prueba: cada `read` entrega del próximo pedazo; `b""` simula un timeout."""

    simulado = True

    def __init__(self, *pedazos: bytes) -> None:
        self.pedazos = list(pedazos)

    def write(self, datos: bytes) -> None:
        pass

    def read(self, n: int, timeout: float | None) -> bytes:
        if not self.pedazos:
            return b""
        datos, self.pedazos[0] = self.pedazos[0][:n], self.pedazos[0][n:]
        if not self.pedazos[0]:
            self.pedazos.pop(0)
        return datos

    def close(self) -> None:
        pass


@pytest.mark.parametrize(
    ("tipo", "payload", "esperado"),
    [
        (TipoTrama.ACK, "", "A5 01 00 00 01"),  # §8.1
        (TipoTrama.NACK, "01", "A5 02 01 00 01 02"),
        (TipoTrama.NACK, "05", "A5 02 01 00 05 06"),
        (TipoTrama.PING_INFO, "01", "A5 04 01 00 01 04"),
        (
            TipoTrama.MEM_DATA,
            "0000 0200 05000000 00000000",
            "A5 05 0C 00 0000 0200 05000000 00000000 0E",
        ),  # §8.9
    ],
)
def test_encode_trama(tipo: TipoTrama, payload: str, esperado: str) -> None:
    assert encode_trama(tipo, bytes.fromhex(payload)) == bytes.fromhex(esperado)


@pytest.mark.parametrize("trama", [ACK, NACK_RANGO, encode_trama(TipoTrama.SNAPSHOT, bytes(221))])
def test_ida_y_vuelta(trama: bytes) -> None:
    lector = FrameReader()
    lector.feed(trama)
    leida = lector.pop()
    assert leida is not None
    assert encode_trama(leida.tipo, leida.payload) == trama
    assert lector.pendientes() == 0


def test_varias_tramas_en_un_pedazo() -> None:
    lector = FrameReader()
    lector.feed(ACK + NACK_RANGO)
    assert lector.pop() == Trama(TipoTrama.ACK, b"")
    assert lector.pop() == Trama(TipoTrama.NACK, bytes([ErrorNack.RANGO]))
    assert lector.pop() is None


def test_trama_de_a_un_byte() -> None:
    lector = FrameReader()
    for b in NACK_RANGO[:-1]:
        lector.feed(bytes([b]))
        assert lector.pop() is None  # incompleta: espera, no falla
    lector.feed(NACK_RANGO[-1:])
    assert lector.pop() == Trama(TipoTrama.NACK, b"\x05")


def test_basura_antes_del_sync_se_descarta() -> None:
    lector = FrameReader()
    lector.feed(bytes.fromhex("00 FF 13") + ACK)
    assert lector.pop() == Trama(TipoTrama.ACK, b"")


@pytest.mark.parametrize(
    ("mala", "error"),
    [
        (bytes.fromhex("A5 02 01 00 05 07"), ErrorChecksum),  # NACK con el XOR cambiado
        (bytes.fromhex("A5 09 00 00 09"), ErrorTipo),  # tipo que no existe
        (bytes.fromhex("A5 01 01 00 00 00"), ErrorLongitud),  # ACK con payload
        (bytes.fromhex("A5 03 DE 00"), ErrorLongitud),  # snapshot de 222 B: no es 221 + 6K
        (bytes.fromhex("A5 05 04 00 00 00 00 00 01"), ErrorLongitud),  # MEM_DATA con n = 0
    ],
)
def test_trama_invalida_no_rompe_la_siguiente(mala: bytes, error: type[ErrorTrama]) -> None:
    lector = FrameReader()
    lector.feed(mala + ACK)
    with pytest.raises(error):
        lector.pop()
    assert lector.pop() == Trama(TipoTrama.ACK, b"")


def test_longitud_imposible_no_espera_los_bytes() -> None:
    # Un A5 FF FF ... corrupto no deja al lector esperando 65535 bytes.
    lector = FrameReader()
    lector.feed(bytes.fromhex("A5 03 FF FF"))
    with pytest.raises(ErrorLongitud):
        lector.pop()


def test_leer_junta_pedazos() -> None:
    transporte = TransportGuionado(NACK_RANGO[:2], NACK_RANGO[2:4], NACK_RANGO[4:])
    assert FrameReader().leer(transporte, timeout=1) == Trama(TipoTrama.NACK, b"\x05")


def test_leer_trama_truncada_y_despues_una_buena() -> None:
    transporte = TransportGuionado(bytes.fromhex("A5 03 DD 00 04 01"), b"", ACK)
    lector = FrameReader()
    with pytest.raises(ErrorTramaTruncada):
        lector.leer(transporte, timeout=1)
    assert lector.leer(transporte, timeout=1) == Trama(TipoTrama.ACK, b"")


def test_leer_sin_respuesta_es_timeout() -> None:
    with pytest.raises(TimeoutError):
        FrameReader().leer(TransportGuionado(), timeout=0)


def test_leer_sin_limite() -> None:
    assert FrameReader().leer(TransportGuionado(ACK), timeout=None) == Trama(TipoTrama.ACK, b"")


def test_errores_son_error_trama() -> None:
    for error in (ErrorChecksum, ErrorTipo, ErrorLongitud, ErrorTramaTruncada, ErrorPayload):
        assert issubclass(error, ErrorTrama)
