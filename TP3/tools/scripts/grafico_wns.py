"""Gráfico del barrido de frecuencia (US-602, ADR-016): WNS según la frecuencia, en SVG.

Uso (desde TP3/tools/):  uv run python -m scripts.grafico_wns   (o `make grafico-wns`)
                         ... --tema claro    --entrada otro.csv    --salida otro.svg

Lee `hw/reports/freq_sweep.csv`, que deja `make freq-sweep` (columnas
`mhz,periodo_ns,wns_ns,whs_ns,tns_ns,cumple`), y escribe `docs/informe/wns_frecuencia.svg`:
grilla en cada frecuencia medida y cada 0,5 ns, el WNS de cada punto, las referencias
WNS = 0 y WNS = 0,3 ns (margen de ADR-016) y la frecuencia óptima marcada.

La óptima es la mayor frecuencia con WNS >= 0,3 ns y WHS >= 0 (el mismo criterio que
`resumen_reportes.py`). El SVG se arma a mano para no sumar dependencias (sin matplotlib).
"""

import argparse
import csv
import math
import sys
from dataclasses import dataclass
from pathlib import Path

TP3 = Path(__file__).resolve().parents[2]
ENTRADA = TP3 / "hw" / "reports" / "freq_sweep.csv"
SALIDA = TP3.parent / "docs" / "informe" / "wns_frecuencia.svg"
MARGEN_WNS = 0.3  # ADR-016
PASO_Y = 0.5  # ns entre líneas de la grilla horizontal
MENOS = "\u2212"  # signo menos tipográfico, más legible que el guion

# Tamaño y márgenes del dibujo (px)
ANCHO, ALTO = 760, 440
IZQ, DER, ARRIBA, ABAJO = 78, 30, 56, 70


@dataclass(frozen=True)
class Tema:
    """Colores de un tema: superficie, textos, grilla, ejes y la serie."""

    superficie: str
    texto: str
    texto2: str
    grilla: str
    eje: str
    serie: str


TEMAS = {
    "oscuro": Tema("#1a1a19", "#f0efec", "#c3c2b7", "#2c2c2a", "#5a5955", "#3987e5"),
    "claro": Tema("#fcfcfb", "#0b0b0b", "#52514e", "#e1e0d9", "#a3a29c", "#2a78d6"),
}


@dataclass(frozen=True)
class Punto:
    """Una frecuencia del barrido."""

    mhz: float
    wns: float
    whs: float


def leer_barrido(ruta: Path) -> list[Punto]:
    """Lee el CSV de `freq_sweep.tcl`, ordenado por frecuencia."""
    with ruta.open(newline="") as f:
        puntos = [
            Punto(float(fila["mhz"]), float(fila["wns_ns"]), float(fila["whs_ns"]))
            for fila in csv.DictReader(f)
        ]
    if not puntos:
        raise ValueError(f"{ruta} no tiene filas")
    return sorted(puntos, key=lambda p: p.mhz)


def optima(puntos: list[Punto]) -> Punto | None:
    """La mayor frecuencia con WNS >= MARGEN_WNS y WHS >= 0 (ADR-016), o None."""
    cumplen = [p for p in puntos if p.wns >= MARGEN_WNS and p.whs >= 0]
    return max(cumplen, key=lambda p: p.mhz) if cumplen else None


def _num(v: float, decimales: int = 3, signo: bool = True) -> str:
    """Número con coma decimal y signo menos tipográfico."""
    texto = f"{v:+.{decimales}f}" if signo else f"{v:.{decimales}f}"
    return texto.replace(".", ",").replace("-", MENOS)


def _mhz(v: float) -> str:
    return f"{v:g}"


def dibujar(puntos: list[Punto], tema: Tema) -> str:
    """Devuelve el SVG del gráfico."""
    pw, ph = ANCHO - IZQ - DER, ALTO - ARRIBA - ABAJO
    fmin, fmax = puntos[0].mhz, puntos[-1].mhz
    margen_x = max((fmax - fmin) * 0.08, 5.0)
    xmin, xmax = fmin - margen_x, fmax + margen_x
    wmin = min(min(p.wns for p in puntos), 0.0)
    wmax = max(max(p.wns for p in puntos), MARGEN_WNS)
    ymin = math.floor((wmin - 0.25) / PASO_Y) * PASO_Y
    ymax = math.ceil((wmax + 0.25) / PASO_Y) * PASO_Y

    def x(f: float) -> float:
        return IZQ + (f - xmin) / (xmax - xmin) * pw

    def y(v: float) -> float:
        return ARRIBA + (ymax - v) / (ymax - ymin) * ph

    t = tema
    s: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{ANCHO}" height="{ALTO}" '
        f'viewBox="0 0 {ANCHO} {ALTO}" font-family="Inter, Segoe UI, Helvetica, Arial, sans-serif" '
        f'role="img" aria-label="WNS según la frecuencia del barrido">',
        f'<rect width="{ANCHO}" height="{ALTO}" rx="8" fill="{t.superficie}"/>',
        f'<text x="{IZQ}" y="26" font-size="16" font-weight="600" fill="{t.texto}">'
        "WNS según la frecuencia (barrido sin MMCM)</text>",
        f'<text x="{IZQ}" y="44" font-size="12" fill="{t.texto2}">Cumple timing con WNS ≥ 0; '
        f"ADR-016 exige además un margen de {_num(MARGEN_WNS, 1, False)} ns</text>",
    ]

    # Grilla horizontal cada PASO_Y y etiquetas del eje Y
    for i in range(round((ymax - ymin) / PASO_Y) + 1):
        v = ymin + i * PASO_Y
        s.append(
            f'<line x1="{IZQ}" y1="{y(v):.1f}" x2="{IZQ + pw}" y2="{y(v):.1f}" '
            f'stroke="{t.grilla}" stroke-width="1"/>'
        )
        s.append(
            f'<text x="{IZQ - 8}" y="{y(v) + 4:.1f}" font-size="11" fill="{t.texto2}" '
            f'text-anchor="end">{_num(v, 1, False)}</text>'
        )
    # Grilla vertical en cada frecuencia medida y etiquetas del eje X
    for p in puntos:
        s.append(
            f'<line x1="{x(p.mhz):.1f}" y1="{ARRIBA}" x2="{x(p.mhz):.1f}" y2="{ARRIBA + ph}" '
            f'stroke="{t.grilla}" stroke-width="1"/>'
        )
        s.append(
            f'<text x="{x(p.mhz):.1f}" y="{ARRIBA + ph + 18}" font-size="11" fill="{t.texto2}" '
            f'text-anchor="middle">{_mhz(p.mhz)}</text>'
        )
    # Ejes y sus títulos
    s += [
        f'<line x1="{IZQ}" y1="{ARRIBA + ph}" x2="{IZQ + pw}" y2="{ARRIBA + ph}" '
        f'stroke="{t.eje}" stroke-width="1"/>',
        f'<line x1="{IZQ}" y1="{ARRIBA}" x2="{IZQ}" y2="{ARRIBA + ph}" '
        f'stroke="{t.eje}" stroke-width="1"/>',
        f'<text x="{IZQ + pw / 2:.1f}" y="{ALTO - 18}" font-size="12" fill="{t.texto2}" '
        'text-anchor="middle">Frecuencia (MHz)</text>',
        f'<text transform="translate(20 {ARRIBA + ph / 2:.1f}) rotate(-90)" font-size="12" '
        f'fill="{t.texto2}" text-anchor="middle">WNS (ns)</text>',
    ]
    # Referencias: WNS = 0 (llena) y margen de ADR-016 (punteada), rotuladas a la izquierda
    xr = IZQ + 10
    s += [
        f'<line x1="{IZQ}" y1="{y(0):.1f}" x2="{IZQ + pw}" y2="{y(0):.1f}" '
        f'stroke="{t.texto2}" stroke-width="1.5"/>',
        f'<text x="{xr}" y="{y(0) + 15:.1f}" font-size="11" fill="{t.texto2}">'
        "WNS = 0 (límite de timing)</text>",
        f'<line x1="{IZQ}" y1="{y(MARGEN_WNS):.1f}" x2="{IZQ + pw}" y2="{y(MARGEN_WNS):.1f}" '
        f'stroke="{t.texto2}" stroke-width="1.5" stroke-dasharray="6 4"/>',
        f'<text x="{xr}" y="{y(MARGEN_WNS) - 6:.1f}" font-size="11" fill="{t.texto2}">'
        f"margen ADR-016 ({_num(MARGEN_WNS, 1, False)} ns)</text>",
    ]
    # Serie: línea de 2 px y un punto por frecuencia
    trazo = " ".join(f"{x(p.mhz):.1f},{y(p.wns):.1f}" for p in puntos)
    s.append(
        f'<polyline points="{trazo}" fill="none" stroke="{t.serie}" stroke-width="2" '
        'stroke-linejoin="round"/>'
    )
    mejor = optima(puntos)
    for i, p in enumerate(puntos):
        px, py = x(p.mhz), y(p.wns)
        es_optima = p == mejor
        s.append(
            f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{6 if es_optima else 4.5}" '
            f'fill="{t.serie}" stroke="{t.superficie}" stroke-width="2"/>'
        )
        if es_optima:
            s.append(
                f'<circle cx="{px:.1f}" cy="{py:.1f}" r="10" fill="none" '
                f'stroke="{t.serie}" stroke-width="1.5"/>'
            )
        tx, ty, ancla = _posicion_etiqueta(puntos, i, px, py)
        peso = "700" if es_optima else "400"
        s.append(
            f'<text x="{tx:.1f}" y="{ty:.1f}" font-size="11" font-weight="{peso}" '
            f'fill="{t.texto}" text-anchor="{ancla}">{_num(p.wns)}</text>'
        )
    # Anotación de la óptima, arriba del punto
    if mejor is not None:
        ox, oy = x(mejor.mhz), y(mejor.wns)
        ay = max(ARRIBA + 14, oy - 80)
        s += [
            f'<text x="{ox:.1f}" y="{ay:.1f}" font-size="12" font-weight="600" fill="{t.texto}" '
            f'text-anchor="middle">{_mhz(mejor.mhz)} MHz: la mayor</text>',
            f'<text x="{ox:.1f}" y="{ay + 15:.1f}" font-size="12" font-weight="600" '
            f'fill="{t.texto}" text-anchor="middle">que cumple el margen</text>',
            f'<line x1="{ox:.1f}" y1="{ay + 22:.1f}" x2="{ox:.1f}" y2="{oy - 26:.1f}" '
            f'stroke="{t.texto2}" stroke-width="1"/>',
        ]
    s.append("</svg>")
    return "\n".join(s) + "\n"


def _posicion_etiqueta(
    puntos: list[Punto], i: int, px: float, py: float
) -> tuple[float, float, str]:
    """Dónde va el valor de un punto para no pisar la serie ni las referencias.

    - primero: a la derecha (la línea sale hacia la derecha y abajo);
    - último: a la izquierda;
    - cerca de una referencia (0 o el margen): arriba a la derecha, entre las dos líneas;
    - negativo: abajo; si no, arriba.
    """
    w = puntos[i].wns
    if i == 0:
        return px + 10, py + 4, "start"
    if i == len(puntos) - 1:
        return px - 10, py + 4, "end"
    cerca_de_cero = abs(w) < 0.15
    cerca_del_margen = abs(w - MARGEN_WNS) < 0.05 and puntos[i] != optima(puntos)
    if cerca_de_cero or cerca_del_margen:
        return px + 8, py - 5, "start"
    if w < 0:
        return px, py + 20, "middle"
    return px, py - 12, "middle"


def main(argv: list[str] | None = None) -> int:
    """Lee el barrido y escribe el SVG. Devuelve 1 si falta el CSV."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--entrada", type=Path, default=ENTRADA, help="CSV de freq_sweep.tcl")
    parser.add_argument("--salida", type=Path, default=SALIDA, help="SVG a escribir")
    parser.add_argument("--tema", choices=sorted(TEMAS), default="oscuro")
    args = parser.parse_args(argv)

    if not args.entrada.exists():
        print(f"No existe {args.entrada}: correr antes `make freq-sweep`", file=sys.stderr)
        return 1
    puntos = leer_barrido(args.entrada)
    args.salida.parent.mkdir(parents=True, exist_ok=True)
    args.salida.write_text(dibujar(puntos, TEMAS[args.tema]), encoding="utf-8")

    mejor = optima(puntos)
    elegida = f"óptima {_mhz(mejor.mhz)} MHz" if mejor else "ninguna cumple el margen"
    print(f"{args.salida}: {len(puntos)} frecuencias, {elegida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
