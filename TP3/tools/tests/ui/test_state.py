"""Habilitación de los controles según el estado (US-501, AC2, AC3 y AC4)."""

import pytest

from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.ui.state import Accion, EstadoUI, acciones_habilitadas

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
