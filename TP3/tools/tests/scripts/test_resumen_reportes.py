"""resumen_reportes contra reportes reales de Vivado (los de la Debug Unit, versionados)."""

from pathlib import Path

import pytest

from scripts.resumen_reportes import (
    REPORTES,
    barrido,
    caminos,
    jerarquia,
    markdown,
    optima,
    potencia,
    rendimiento,
    resumen_timing,
    tabla_util,
)


def _leer(nombre: str) -> str:
    return (REPORTES / nombre).read_text(encoding="utf-8")


def test_resumen_de_timing() -> None:
    r = resumen_timing(_leer("du_ooc_timing_summary.rpt"))
    assert (r["wns"], r["tns"], r["whs"], r["endpoints"]) == (1.873, 0.0, 0.149, 1424)


def test_el_peor_camino_con_su_desglose() -> None:
    cs = caminos(_leer("du_ooc_timing_setup.rpt"))
    assert len(cs) == 10
    peor = cs[0]
    assert (peor.slack, peor.skew, peor.retardo_datos) == (1.873, -0.049, 8.120)
    assert peor.origen == "u_dumper/r_pos_reg[1]/C"
    assert peor.destino == "u_dumper/r_xor_reg[7]/D"
    assert peor.niveles.startswith("7")
    # Los tramos suman lo que dice el encabezado (incluida la línea partida del CARRY4)
    logica = [p for p in peor.pasos if p.tipo == "logica"]
    assert [p.que for p in logica][:2] == ["FDRE", "CARRY4"]
    assert sum(p.retardo for p in logica) == pytest.approx(peor.logica, abs=0.002)
    assert sum(p.retardo for p in peor.pasos if p.tipo == "ruteo") == pytest.approx(
        peor.ruteo, abs=0.002
    )
    assert [c.slack for c in cs] == sorted(c.slack for c in cs)


def test_caminos_de_hold() -> None:
    cs = caminos(_leer("du_ooc_timing_hold.rpt"))
    assert cs[0].slack == 0.149
    assert all(c.requerido == 0.0 for c in cs)


def test_utilizacion_total_y_por_modulo() -> None:
    u = tabla_util(_leer("du_ooc_util.rpt"))
    assert u["Slice LUTs"] == ("889", "20800", "4.27")
    assert u["Slice Registers"][0] == "1049"
    filas = jerarquia(_leer("du_ooc_util_hier.rpt"))
    assert filas[0][:3] == ["debug_unit", "(top)", "889"]
    assert ["  u_dumper", "du_dumper", "598"] in [f[:3] for f in filas]


def test_potencia() -> None:
    texto = (
        "| Total On-Chip Power (W)  | 0.093        |\n"
        "| Design Power Budget (W)  | Unspecified* |\n"
        "| Dynamic (W)              | 0.021        |\n"
        "| Clocks         |     0.004 |        3 |       --- |             --- |\n"
    )
    p = potencia(texto)
    assert (p["Total On-Chip Power (W)"], p["Dynamic (W)"], p["Clocks"]) == (
        "0.093",
        "0.021",
        "0.004",
    )
    assert "Design Power Budget (W)" not in p


def test_optima_del_barrido() -> None:
    filas = barrido(
        "mhz,periodo_ns,wns_ns,whs_ns,tns_ns,cumple\n"
        "100,10.000,1.200,0.050,0.000,si\n"
        "125,8.000,0.250,0.040,0.000,no\n"  # WNS < 0,3: no alcanza el margen de ADR-016
        "110,9.091,0.400,0.045,0.000,si\n"
    )
    mejor = optima(filas)
    assert mejor is not None
    assert mejor["mhz"] == "110"
    assert optima(filas[1:2]) is None


def test_markdown_sin_reportes_dice_como_generarlos(tmp_path: Path) -> None:
    texto = markdown(tmp_path)
    assert "correr `make impl`" in texto
    assert "correr `make freq-sweep`" in texto


def test_rendimiento_separa_stalls_y_control() -> None:
    filas = rendimiento(
        "programa,resultado,ciclos,instrucciones,cpi,stalls,flush_if_id,flush_id_ex\n"
        "tests/hazards/load_use,OK,14,9,1.556,1,0,0\n"  # 9 + 4 + 1 stall
        "demos/x,OK,30,20,1.5,2,4,4\n"  # 30 - 20 - 4 = 6 perdidos: 2 stalls, 4 de control
        "special/infinite_loop,OMITIDO,0,0,0,0,0,0\n"
    )
    assert [(f["perdidos"], f["stalls"], f["control"]) for f in filas] == [(1, 1, 0), (6, 2, 4)]
