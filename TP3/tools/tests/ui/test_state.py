"""Lógica de la GUI sin Flet (US-501): habilitación (AC2-AC4), línea resaltada (AC5-AC6)."""

from dataclasses import replace

import pytest

from riscv_toolkit.protocol.comandos import EstadoDU, Motivo
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    RiesgosCiclo,
    Snapshot,
)
from riscv_toolkit.ui.state import (
    Accion,
    EstadoUI,
    Etapa,
    acciones_habilitadas,
    contar_riesgos,
    linea_de,
    pc_resaltado,
    rango_de_linea,
)

A = Accion
NINGUNA: frozenset[Accion] = frozenset()


@pytest.mark.parametrize(
    ("estado_du", "esperadas"),
    [
        (EstadoDU.IDLE, {A.CARGAR, A.RESET}),
        (EstadoDU.READY, {A.CARGAR, A.CORRER, A.PASO, A.RESET}),
        (EstadoDU.STEPPING, {A.CARGAR, A.CORRER, A.PASO, A.RESET}),
        (EstadoDU.HALTED, {A.CARGAR, A.RESET}),
        (EstadoDU.RUN, {A.ABORTAR}),
        (EstadoDU.LOADING, NINGUNA),
        (EstadoDU.DUMPING, NINGUNA),
        (None, NINGUNA),
    ],
)
def test_espejo_de_r_du_1(estado_du: EstadoDU | None, esperadas: set[Accion]) -> None:
    estado = EstadoUI(conectado=True, estado_du=estado_du, imagen_valida=True)
    assert acciones_habilitadas(estado) == esperadas


@pytest.mark.parametrize("estado_du", [*EstadoDU, None])
def test_desconectado_no_habilita_nada(estado_du: EstadoDU | None) -> None:
    estado = EstadoUI(conectado=False, estado_du=estado_du, imagen_valida=True)
    assert acciones_habilitadas(estado) == NINGUNA


@pytest.mark.parametrize(
    ("estado_du", "esperadas"),
    [
        (EstadoDU.IDLE, {A.RESET}),
        (EstadoDU.READY, {A.CORRER, A.PASO, A.RESET}),
        (EstadoDU.HALTED, {A.RESET}),
    ],
)
def test_sin_imagen_valida_no_se_puede_cargar(estado_du: EstadoDU, esperadas: set[Accion]) -> None:
    # AC2: con un error de ensamblado (o el texto editado después de ensamblar) no se carga,
    # pero lo que ya está en la placa se puede seguir corriendo.
    estado = EstadoUI(conectado=True, estado_du=estado_du, imagen_valida=False)
    assert acciones_habilitadas(estado) == esperadas


@pytest.mark.parametrize("estado_du", [EstadoDU.IDLE, EstadoDU.READY, EstadoDU.HALTED])
def test_ocupado_bloquea_todo(estado_du: EstadoDU) -> None:
    # Un segundo clic mientras el worker atiende otro comando mezclaría dos transacciones.
    estado = EstadoUI(conectado=True, estado_du=estado_du, imagen_valida=True, ocupado=True)
    assert acciones_habilitadas(estado) == NINGUNA


def test_ocupado_en_run_deja_abortar() -> None:
    # AC4: durante un RUN el worker está ocupado esperando, y Abortar tiene que andar.
    estado = EstadoUI(conectado=True, estado_du=EstadoDU.RUN, imagen_valida=True, ocupado=True)
    assert acciones_habilitadas(estado) == {A.ABORTAR}


# --- Línea en ejecución (AC5 y AC6) --------------------------------------------------------

BASE = Snapshot(EstadoDU.STEPPING, None, 5, 0x10, RiesgosCiclo(), (0,) * 32,
                LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB())  # fmt: skip
EN_WB = LatchMEMWB(pc_plus4=0x08, valid=True)


def test_if_sigue_al_pc() -> None:
    assert pc_resaltado(BASE, Etapa.IF) == 0x10


def test_wb_sigue_a_mem_wb() -> None:
    assert pc_resaltado(replace(BASE, mem_wb=EN_WB), Etapa.WB) == 0x04


def test_wb_con_burbuja_no_resalta() -> None:
    assert pc_resaltado(BASE, Etapa.WB) is None


@pytest.mark.parametrize("motivo", [Motivo.HALTED, Motivo.ABORTED])
def test_terminado_no_resalta(motivo: Motivo) -> None:
    snap = replace(BASE, estado=EstadoDU.HALTED, motivo=motivo)
    assert pc_resaltado(snap, Etapa.IF) is None


@pytest.mark.parametrize("etapa", list(Etapa))
def test_illegal_resalta_la_ilegal_en_mem_wb(etapa: Etapa) -> None:
    ilegal = LatchMEMWB(pc_plus4=0x0C, valid=True, illegal=True)
    snap = replace(BASE, estado=EstadoDU.HALTED, motivo=Motivo.ILLEGAL, mem_wb=ilegal)
    assert pc_resaltado(snap, etapa) == 0x08


def test_illegal_con_pipeline_vacio_usa_el_pc() -> None:
    # Así queda el FakeTransport: el golden model deja el PC en la instrucción ilegal.
    snap = replace(BASE, estado=EstadoDU.HALTED, motivo=Motivo.ILLEGAL)
    assert pc_resaltado(snap, Etapa.WB) == 0x10


def test_contar_riesgos() -> None:
    snaps = [
        replace(BASE, riesgos=RiesgosCiclo(stall=True)),
        replace(BASE, riesgos=RiesgosCiclo(flush_if_id=True, flush_id_ex=True)),  # uno solo
        replace(BASE, riesgos=RiesgosCiclo(stall=True, flush_id_ex=True)),
        BASE,
    ]
    assert contar_riesgos(snaps) == (2, 2)


# --- Posiciones en el texto ----------------------------------------------------------------

TEXTO = "addi x1, x0, 1\n\nhalt"


@pytest.mark.parametrize(("offset", "linea"), [(0, 1), (14, 1), (15, 2), (16, 3), (20, 3)])
def test_linea_de(offset: int, linea: int) -> None:
    assert linea_de(TEXTO, offset) == linea


@pytest.mark.parametrize(
    ("linea", "rango"), [(1, (0, 14)), (2, (15, 15)), (3, (16, 20)), (0, (20, 20)), (9, (20, 20))]
)
def test_rango_de_linea(linea: int, rango: tuple[int, int]) -> None:
    assert rango_de_linea(TEXTO, linea) == rango
