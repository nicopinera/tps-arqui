"""Genera el fondo y el mapa de la vista Datapath de la GUI desde `docs/diagramas/`.

Uso (desde TP3/tools/, en Windows con Edge):  uv run python -m scripts.gen_datapath

Escribe en `riscv_toolkit/ui/assets/datapath/`:
- `datapath.png`: el SVG exportado de draw.io, dibujado por Edge en modo claro. Flet no puede
  mostrar el SVG directo: el texto está en `foreignObject` (HTML) y los colores en
  `light-dark()`, y `flutter_svg` no entiende ninguno de los dos.
- `datapath.json`: dónde está cada etiqueta, cada latch, cada mux (y qué cable entra por cada
  entrada) y los cables agrupados en redes, en las coordenadas del PNG.

Hay que correrlo cada vez que cambia el `.drawio` (y su exportación a SVG); un test avisa si el
JSON quedó desactualizado.
"""

import hashlib
import html
import itertools
import json
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

DIAGRAMAS = Path(__file__).resolve().parents[3] / "docs" / "diagramas"
DRAWIO = DIAGRAMAS / "datapath_pipeline.drawio"
SVG = DIAGRAMAS / "datapath_pipeline.svg"
SALIDA = Path(__file__).resolve().parents[1] / "riscv_toolkit" / "ui" / "assets" / "datapath"
PAGINA = "tp3-datapath"  # la página del .drawio que se exporta (la otra es la Fig. 7.61)
LATCHES = ("IF/ID", "ID/EX", "EX/MEM", "MEM/WB")
EDGE = (
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
)

Punto = tuple[float, float]
Rect = list[float]  # x, y, ancho, alto


def _texto(celda: ET.Element) -> str:
    """El texto visible de una celda (el `value` es HTML)."""
    return " ".join(re.sub(r"<[^>]+>", " ", html.unescape(celda.get("value") or "")).split())


def _rect(celda: ET.Element, dx: float, dy: float) -> Rect:
    g = celda.find("mxGeometry")
    if g is None:
        sys.exit(f"la celda {celda.get('id')} no tiene mxGeometry")
    return [float(g.get(k, 0)) + d for k, d in (("x", dx), ("y", dy))] + [
        float(g.get("width", 0)),
        float(g.get("height", 0)),
    ]


def _hash(ruta: Path) -> str:
    """Sin depender de los fines de línea: git los cambia según el sistema (autocrlf)."""
    return hashlib.sha256(ruta.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def _caminos(svg: str) -> dict[str, list[Punto]]:
    """id del cable → sus puntos, del primer `<path d>` de su grupo en el SVG."""
    caminos = {}
    for m in re.finditer(r'data-cell-id="([^"]+)"><g[^>]*><path d="([^"]*)"', svg):
        puntos = [(float(x), float(y)) for x, y in re.findall(r"([-\d.]+) ([-\d.]+)", m.group(2))]
        caminos[m.group(1)] = puntos
    return caminos


def _sobre(p: Punto, a: Punto, b: Punto, tol: float = 1.5) -> bool:
    """¿El punto `p` cae sobre el segmento a-b? (los cables son horizontales o verticales)"""
    (x, y), (x1, y1), (x2, y2) = p, a, b
    return (
        min(x1, x2) - tol <= x <= max(x1, x2) + tol and min(y1, y2) - tol <= y <= max(y1, y2) + tol
    )


def redes(cables: list[list[Punto]]) -> list[int]:
    """A qué red pertenece cada cable: dos cables se tocan si un extremo de uno cae sobre el otro.

    Así se reconstruyen las uniones (los puntos en T) del dibujo: el .drawio no las guarda,
    son cables sueltos que se tocan. Dos cables que se cruzan sin tocarse con un extremo no
    se unen, igual que en un esquemático.
    """
    padre = list(range(len(cables)))

    def raiz(i: int) -> int:
        while padre[i] != i:
            padre[i] = padre[padre[i]]
            i = padre[i]
        return i

    for i, ci in enumerate(cables):
        for j, cj in enumerate(cables):
            if i != j and any(
                _sobre(p, a, b) for p in (ci[0], ci[-1]) for a, b in itertools.pairwise(cj)
            ):
                padre[raiz(i)] = raiz(j)
    raices = sorted({raiz(i) for i in range(len(cables))})
    return [raices.index(raiz(i)) for i in range(len(cables))]


def generar_mapa() -> dict[str, object]:
    """El contenido de `datapath.json`, sin escribir nada en disco."""
    svg = SVG.read_text(encoding="utf-8")
    raiz = ET.parse(DRAWIO).getroot()  # noqa: S314 (es nuestro, del repo)
    pagina = next(d for d in raiz.iter("diagram") if d.get("id") == PAGINA)
    celdas = {c.get("id", ""): c for c in pagina.iter("mxCell")}

    # draw.io recorta el dibujo al exportar: el SVG está corrido respecto del .drawio.
    ancla = re.search(r'data-cell-id="tp3-1"><g><rect x="([\d.]+)" y="([\d.]+)"', svg)
    g1 = celdas["tp3-1"].find("mxGeometry")
    if ancla is None or g1 is None:
        sys.exit("no está la celda tp3-1 (el ancla) en el SVG o en el .drawio")
    dx = float(ancla.group(1)) - float(g1.get("x", 0))
    dy = float(ancla.group(2)) - float(g1.get("y", 0))
    tam = re.search(r'width="(\d+)px" height="(\d+)px"', svg)
    if tam is None:
        sys.exit("el SVG no dice su tamaño en px")

    etiquetas: list[dict[str, Any]] = []
    bloques: list[dict[str, Any]] = []
    muxes: dict[str, list[str]] = {}
    for i, c in celdas.items():
        if c.get("vertex") != "1":
            continue
        estilo, texto = c.get("style") or "", _texto(c)
        if estilo.startswith("text") and texto:
            tamaño = re.search(r"fontSize=(\d+)", estilo)
            alinea = re.search(r"align=(left|center|right)", estilo)
            etiquetas.append(
                {"id": i, "texto": texto, "rect": _rect(c, dx, dy),
                 "letra": int(tamaño.group(1)) if tamaño else 11,
                 "alinea": alinea.group(1) if alinea else "center"}
            )  # fmt: skip
        elif not estilo.startswith("text"):
            bloques.append({"id": i, "texto": texto, "rect": _rect(c, dx, dy)})
            opciones = texto.split()
            if "trapezoid" in estilo and opciones and all(set(o) <= {"0", "1"} for o in opciones):
                muxes[i] = opciones

    caminos = _caminos(svg)
    ids = [
        c.get("id", "") for c in celdas.values() if c.get("edge") == "1" and c.get("id") in caminos
    ]
    cables = [caminos[i] for i in ids]
    red = redes(cables)

    def debajo(nombre: str, alto_minimo: float) -> Rect:
        """El bloque que está justo debajo de un título: la barra de un latch, el registro PC."""
        t = next(e["rect"] for e in etiquetas if e["texto"] == nombre)
        centro = t[0] + t[2] / 2
        return min(
            (b["rect"] for b in bloques
             if b["rect"][3] >= alto_minimo and b["rect"][1] >= t[1]
             and abs(b["rect"][0] + b["rect"][2] / 2 - centro) < 15),
            key=lambda r: r[1],
        )  # fmt: skip

    entradas: dict[str, list[dict[str, object]]] = {}
    for i, opciones in muxes.items():
        x, y, _, alto = next(b["rect"] for b in bloques if b["id"] == i)
        # Las entradas llegan por el borde izquierdo, de arriba abajo en el orden del rótulo.
        llegan = sorted(
            (p[1], red[k]) for k, cable in enumerate(cables) for p in (cable[0], cable[-1])
            if abs(p[0] - x) <= 1.5 and y < p[1] < y + alto
        )  # fmt: skip
        if len(llegan) != len(opciones):
            sys.exit(f"mux {i}: {len(llegan)} cables para las entradas {opciones}")
        entradas[i] = [{"opcion": o, "red": r} for o, (_, r) in zip(opciones, llegan, strict=True)]

    return {
        "drawio_sha256": _hash(DRAWIO),
        "svg_sha256": _hash(SVG),
        "ancho": int(tam.group(1)),
        "alto": int(tam.group(2)),
        "etiquetas": etiquetas,
        # El rótulo "PC" está corrido del registro: ahí va por id (tp3-27).
        "latches": {n: debajo(n, 500) for n in LATCHES} | {"PC": _rect(celdas["tp3-27"], dx, dy)},
        "bloques": {b["id"]: b["rect"] for b in bloques},
        "muxes": entradas,
        "redes": [[[list(p) for p in c] for k, c in enumerate(cables) if red[k] == n]
                  for n in range(max(red) + 1)],
    }  # fmt: skip


def _dibujar_png(ancho: int, alto: int, destino: Path) -> None:
    """El SVG en modo claro, con el tamaño exacto (1 px del PNG = 1 unidad del SVG)."""
    edge = next((e for e in EDGE if e.exists()), None) or shutil.which("msedge")
    if edge is None:
        sys.exit("No encontré Microsoft Edge: hace falta para dibujar el SVG.")
    with tempfile.TemporaryDirectory() as tmp:
        claro = Path(tmp) / "datapath.svg"
        texto = SVG.read_text(encoding="utf-8").replace(
            "color-scheme: light dark;", "color-scheme: light;"
        )
        claro.write_text(texto, encoding="utf-8")
        subprocess.run(  # noqa: S603 (Edge de una ruta fija, archivos nuestros)
            [str(edge), "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--force-device-scale-factor=1", f"--window-size={ancho},{alto}",
             f"--screenshot={destino}", claro.as_uri()],
            check=True, capture_output=True,
        )  # fmt: skip


def main() -> None:
    mapa = generar_mapa()
    SALIDA.mkdir(parents=True, exist_ok=True)
    (SALIDA / "datapath.json").write_text(json.dumps(mapa, ensure_ascii=False), encoding="utf-8")
    _dibujar_png(int(str(mapa["ancho"])), int(str(mapa["alto"])), SALIDA / "datapath.png")
    print(f"Escrito {SALIDA / 'datapath.json'} y datapath.png")


if __name__ == "__main__":
    main()
