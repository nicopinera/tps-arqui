"""Coherencia de las constantes del protocolo (US-104, docs/protocolo.md)."""

from enum import IntEnum

import pytest

from riscv_toolkit.protocol import comandos as c

ENUMS = [c.Comando, c.TipoTrama, c.ErrorNack, c.EstadoDU, c.Motivo]


@pytest.mark.parametrize("enum", ENUMS)
def test_sin_valores_repetidos(enum: type[IntEnum]) -> None:
    # Un valor repetido no da error: el segundo nombre queda como alias y desaparece de list(enum).
    assert len(enum.__members__) == len(list(enum))


@pytest.mark.parametrize("enum", ENUMS)
def test_valores_entran_en_un_byte(enum: type[IntEnum]) -> None:
    assert all(0 <= m <= 0xFF for m in enum)


def test_comando_es_su_letra_ascii() -> None:
    letras = {"LOAD": "L", "RUN": "R", "STEP": "S", "DUMP": "D", "RESET": "X", "ABORT": "A"}
    letras |= {"PING": "?", "DUMP_MEM": "M"}
    assert {m.name: chr(m) for m in c.Comando} == letras


def test_errores_no_usan_cero() -> None:
    assert 0 not in list(c.ErrorNack)


@pytest.mark.parametrize("enum", [c.EstadoDU, c.Motivo])
def test_estado_y_motivo_entran_en_un_nibble(enum: type[IntEnum]) -> None:
    assert max(enum) <= 0xF


def test_tamano_fijo_del_snapshot() -> None:
    # AC2: la suma de los bloques de §6.2 es la longitud del payload con K = 0.
    assert c.SNAPSHOT_FIJO == 221


def test_snapshot_maximo_entra_en_el_campo_longitud() -> None:
    assert c.SNAPSHOT_FIJO + c.SNAP_PALABRA_USADA * c.DMEM_DEPTH <= 0xFFFF
