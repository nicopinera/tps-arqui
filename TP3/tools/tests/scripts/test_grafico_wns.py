import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

from scripts.grafico_wns import ENTRADA, MARGEN_WNS, MENOS, Punto, leer_barrido, main, optima

CSV = """mhz,periodo_ns,wns_ns,whs_ns,tns_ns,cumple
100,10.000,-1.145,0.039,-8.953,no
50,20.000,4.760,0.057,0.000,si
85,11.765,0.324,0.049,0.000,si
90,11.111,0.028,0.047,0.000,no
"""


@pytest.fixture
def barrido(tmp_path: Path) -> Path:
    ruta = tmp_path / "freq_sweep.csv"
    ruta.write_text(CSV)
    return ruta


def test_lee_el_csv_ordenado_por_frecuencia(barrido: Path) -> None:
    assert [p.mhz for p in leer_barrido(barrido)] == [50, 85, 90, 100]


def test_la_optima_es_la_mayor_con_margen_y_hold(barrido: Path) -> None:
    mejor = optima(leer_barrido(barrido))
    assert mejor is not None
    assert mejor.mhz == 85  # 90 cumple timing (WNS > 0) pero no el margen de 0,3 ns


def test_sin_hold_no_cuenta_como_optima() -> None:
    assert optima([Punto(50, 1.0, -0.01)]) is None
    assert optima([Punto(50, MARGEN_WNS, 0.0)]) == Punto(50, MARGEN_WNS, 0.0)


@pytest.mark.parametrize("tema", ["oscuro", "claro"])
def test_escribe_un_svg_valido_con_cada_punto(barrido: Path, tmp_path: Path, tema: str) -> None:
    salida = tmp_path / "wns.svg"
    assert main(["--entrada", str(barrido), "--salida", str(salida), "--tema", tema]) == 0
    # El SVG lo acaba de generar el script: no es un XML de afuera
    raiz = ET.fromstring(salida.read_text(encoding="utf-8"))  # noqa: S314
    textos = [t.text for t in raiz.iter("{http://www.w3.org/2000/svg}text")]
    for valor in ["+4,760", "+0,324", "+0,028", f"{MENOS}1,145"]:
        assert valor in textos
    assert "85 MHz: la mayor" in textos
    circulos = list(raiz.iter("{http://www.w3.org/2000/svg}circle"))
    assert len(circulos) == 4 + 1  # un punto por frecuencia y el anillo de la óptima


def test_sin_csv_sale_con_error(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--entrada", str(tmp_path / "no.csv"), "--salida", str(tmp_path / "x.svg")]) == 1
    assert "make freq-sweep" in capsys.readouterr().err


def test_el_csv_versionado_se_puede_graficar(tmp_path: Path) -> None:
    salida = tmp_path / "wns.svg"
    assert main(["--entrada", str(ENTRADA), "--salida", str(salida)]) == 0
    assert salida.stat().st_size > 0
