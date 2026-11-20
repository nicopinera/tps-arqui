"""El mapa de la vista Datapath (`scripts/gen_datapath.py`) está al día con el `.drawio`."""

import json

from scripts.gen_datapath import SALIDA, generar_mapa, redes


def test_el_json_esta_al_dia_con_el_drawio() -> None:
    en_disco = json.loads((SALIDA / "datapath.json").read_text(encoding="utf-8"))
    assert en_disco == json.loads(json.dumps(generar_mapa())), (
        "datapath.json desactualizado: correr `uv run python -m scripts.gen_datapath` desde "
        "tools/ (en Windows, con Edge) y commitear el .json y el .png"
    )


def test_el_mapa_tiene_lo_que_usa_la_vista() -> None:
    mapa = generar_mapa()
    nombres = {e["texto"].split()[0] for e in mapa["etiquetas"]}  # type: ignore[attr-defined]
    assert {"rs1E", "alu_resultM", "ResultW", "fwd_a", "StallF", "pc_sel", "srcA"} <= nombres
    muxes = mapa["muxes"]
    assert isinstance(muxes, dict)
    # Los dos muxes de forwarding: las entradas 01 y 10 son las mismas dos redes (ResultW y
    # alu_resultM), y la 00 es distinta en cada uno (rs1_dataE / rs2_dataE).
    a, b = ({e["opcion"]: e["red"] for e in muxes[m]} for m in ("tp3-207", "tp3-208"))
    assert (a["01"], a["10"]) == (b["01"], b["10"])
    assert a["00"] != b["00"]


def test_redes_une_los_cables_que_se_tocan_con_un_extremo() -> None:
    cables = [
        [(0.0, 0.0), (10.0, 0.0)],  # 0: horizontal
        [(5.0, 0.0), (5.0, 10.0)],  # 1: sale del medio del 0 (una T): misma red
        [(20.0, -5.0), (20.0, 5.0)],  # 2: suelto
        [(15.0, 5.0), (25.0, 5.0)],  # 3: el extremo de abajo del 2 cae sobre este
        [(0.0, 3.0), (30.0, 3.0)],  # 4: cruza al 1 y al 2 sin extremos encima: otra red
    ]
    r = redes(cables)
    assert r[0] == r[1]
    assert r[2] == r[3]  # el extremo (20, 5) del 2 cae sobre el 3
    assert len({r[0], r[2], r[4]}) == 3
