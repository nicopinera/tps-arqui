"""Vista Datapath sin Flet: valor de cada señal del diagrama y qué se resalta."""

from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.iss.pipeline_model import ModeloPipeline
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.ui.datapath import (
    MUX_SELECTOR,
    Valor,
    cargar_mapa,
    formatear,
    nombre_de,
    resaltes,
    valores_datapath,
)

HAZARDS = Path(__file__).parents[3] / "asm" / "tests" / "hazards"
NOMBRES = {nombre_de(e["texto"]) for e in cargar_mapa()["etiquetas"]}


def snapshots(programa: str) -> tuple[list[int], list[Snapshot]]:
    palabras = ensamblar((HAZARDS / programa).read_text(encoding="utf-8")).palabras
    modelo = ModeloPipeline(palabras)
    snaps = [modelo.snapshot()]
    while modelo.motivo is None:
        modelo.ciclo()
        snaps.append(modelo.snapshot())
    return palabras, snaps


@pytest.mark.parametrize(
    ("nombre", "valor", "texto"),
    [
        ("validE", 1, "1"),
        ("StallF", 0, "0"),
        ("fwd_a", 0b10, "10"),
        ("result_srcW", 1, "01"),
        ("imm_type", 0b101, "101"),
        ("funct3", 2, "010"),
        ("rs1D", 5, "x5"),
        ("rdW", 31, "x31"),
        ("instrD", 0x93, "00000093"),
        ("alu_resultM", 0x1C, "0x1c"),
        ("rs1_dataE", 7, "0x7"),  # es el dato, no el número de registro
        ("branch_target", 0x10, "0x10"),  # no es el bit `branch`
    ],
)
def test_formatear(nombre: str, valor: int, texto: str) -> None:
    assert formatear(nombre, valor) == texto


def test_load_use_ciclo_del_stall() -> None:
    palabras, snaps = snapshots("load_use.asm")
    v = valores_datapath(snaps[4], palabras, NOMBRES)
    # Medidos: los latches del snapshot. lw x2 en EX, add x2,x2,x2 en ID.
    assert v["rdE"] == Valor("x2", True)
    assert v["mem_readE"] == Valor("1", True)
    assert v["instrD"] == Valor(f"{palabras[3]:08x}", True)
    # Calculados por el modelo: la Hazard Unit.
    assert v["StallF"] == Valor("1", False)
    assert v["rs1D"] == Valor("x2", False)
    assert v["uses_rs1D"] == v["uses_rs1"] == Valor("1", False)
    r = resaltes(v)
    assert r.bloques == {"PC": "st", "IF/ID": "st", "ID/EX": "st"}


def test_load_use_forwarding_desde_mem_wb() -> None:
    palabras, snaps = snapshots("load_use.asm")
    v = valores_datapath(snaps[6], palabras, NOMBRES)
    assert v["fwd_a"] == v["fwd_b"] == Valor("01", True)
    assert v["srcA"] == Valor("0x7", False)
    r = resaltes(v)
    assert r.muxes["tp3-207"] == ("01", "fa")
    assert r.muxes["tp3-208"] == ("01", "fb")
    assert r.muxes["tp3-209"] == ("0", None)  # add: srcB es el operando, no el inmediato
    assert r.bloques == {}


def test_branch_tomado_vacia_if_id_e_id_ex() -> None:
    palabras, snaps = snapshots("branch_taken.asm")
    v = valores_datapath(snaps[3], palabras, NOMBRES)
    assert v["redirect_ex"] == Valor("1", False)
    assert v["ex_target"] == Valor("0x10", False)
    r = resaltes(v)
    assert r.bloques == {"IF/ID": "fl", "ID/EX": "fl"}
    assert r.muxes["tp3-26"] == ("10", "fl")  # pc_sel: el destino de EX


def test_sin_programa_solo_los_medidos() -> None:
    _, snaps = snapshots("load_use.asm")
    v = valores_datapath(snaps[4], None, NOMBRES)
    assert all(x.medido for x in v.values())
    assert "rdE" in v
    assert "srcA" not in v


def test_los_muxes_existen_en_el_mapa() -> None:
    assert set(MUX_SELECTOR) == set(cargar_mapa()["muxes"])
