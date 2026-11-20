"""Constantes del protocolo (docs/protocolo.md).

Fuente de verdad en código: `scripts/gen_du_defs.py` genera `hw/rtl/debug/du_defs.vh` desde
este archivo. Cambiar un valor acá obliga a regenerar el `.vh` (lo verifica
`tests/protocol/test_du_defs_sync.py`) y, si cambia el protocolo, a subir `PROTO_VERSION`.
"""

from enum import IntEnum
from typing import Final

# --- Constantes compartidas ----------------------------------------------

PROTO_VERSION: Final = 0x01  # payload de PING_INFO
SYNC: Final = 0xA5  # primer byte de toda trama FPGA → PC (ADR-003)
IMEM_DEPTH: Final = 0x100  # palabras de la IMEM: 256 (ADR-008)
DMEM_DEPTH: Final = 0x100  # palabras de la DMEM: 256 (ADR-008)
SIGNATURE_ADDR: Final = 0x3FC  # dirección en bytes de la firma de los tests (ADR-014)
RX_TIMEOUT_MS: Final = 0x64  # timeout de recepción en hardware: 100 ms (R-DU-6, protocolo §7.3)

# --- Tamaños del payload SNAPSHOT en bytes ---------------------

SNAP_CABECERA: Final = 0x09  # estado (1) + ciclos (4) + PC (4)
SNAP_RIESGOS: Final = 0x01
SNAP_REGISTROS: Final = 0x80  # x0 … x31, 4 B cada uno
SNAP_IF_ID: Final = 0x0D
SNAP_ID_EX: Final = 0x1F
SNAP_EX_MEM: Final = 0x13
SNAP_MEM_WB: Final = 0x12
SNAP_CANT_USADAS: Final = 0x02  # K
SNAP_PALABRA_USADA: Final = 0x06  # dirección (2) + dato (4), se repite K veces

SNAPSHOT_FIJO: Final = (
    SNAP_CABECERA
    + SNAP_RIESGOS
    + SNAP_REGISTROS
    + SNAP_IF_ID
    + SNAP_ID_EX
    + SNAP_EX_MEM
    + SNAP_MEM_WB
    + SNAP_CANT_USADAS
)  # 221: longitud del payload con K = 0


class Comando(IntEnum):
    """Byte de comando PC → FPGA."""

    LOAD = 0x4C  # 'L'
    RUN = 0x52  # 'R'
    STEP = 0x53  # 'S'
    DUMP = 0x44  # 'D'
    RESET = 0x58  # 'X'
    ABORT = 0x41  # 'A'
    PING = 0x3F  # '?'
    DUMP_MEM = 0x4D  # 'M'


class TipoTrama(IntEnum):
    """Campo `tipo` de las tramas FPGA → PC."""

    ACK = 0x01
    NACK = 0x02
    SNAPSHOT = 0x03
    PING_INFO = 0x04
    MEM_DATA = 0x05


class ErrorNack(IntEnum):
    """Código de error del payload de NACK. El 0x00 no se usa."""

    DESCONOCIDO = 0x01
    ESTADO = 0x02
    CHECKSUM = 0x03
    TAMANO = 0x04
    RANGO = 0x05
    TIMEOUT = 0x06
    PARIDAD = 0x07


class EstadoDU(IntEnum):
    """Estado de la FSM de la Debug Unit; nibble bajo del byte `estado`."""

    IDLE = 0x0
    LOADING = 0x1
    READY = 0x2
    RUN = 0x3
    STEPPING = 0x4
    DUMPING = 0x5
    HALTED = 0x6


class Motivo(IntEnum):
    """Motivo de terminación; nibble alto del byte `estado`."""

    NINGUNO = 0x0
    HALTED = 0x1
    ILLEGAL = 0x2
    ABORTED = 0x3
