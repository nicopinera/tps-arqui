"""Tablas en Markdown de los reportes de Vivado del sistema completo (Hito 6), sin Vivado.

Uso (desde TP3/tools/):  uv run python -m scripts.resumen_reportes   (o `make reportes`)

Lee de `hw/reports/` lo que dejan `make impl` y `make freq-sweep`:
- `top_timing_summary.rpt`: WNS/TNS/WHS/THS (US-601);
- `top_timing_setup.rpt` y `top_timing_hold.rpt`: los 10 peores caminos, con su skew, y el
  peor de setup paso a paso (celda por celda, lógica contra ruteo);
- `freq_sweep.csv`: el barrido de frecuencia y la óptima según ADR-016 (US-602);
- `top_util.rpt`, `top_util_hier.rpt` y `top_power.rpt`: recursos y potencia (US-603);
- `docs/informe/datos/cpi.csv` (de `make verify`): CPI y ciclos perdidos por programa (US-603).

Escribe `docs/informe/datos/reportes_vivado.md`, de donde salen los números de `timing.md` y
`metricas.md` (US-604 AC3: ningún número del informe se escribe a mano). Si falta un reporte,
su sección dice qué comando lo genera.
"""

import csv
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

TP3 = Path(__file__).resolve().parents[2]
REPORTES = TP3 / "hw" / "reports"
SALIDA = TP3.parent / "docs" / "informe" / "datos" / "reportes_vivado.md"
CPI_CSV = TP3.parent / "docs" / "informe" / "datos" / "cpi.csv"  # lo escribe `make verify`
LLENADO = 4  # ciclos hasta que la primera instrucción llega a WB
MARGEN_WNS = 0.3  # ADR-016

_NUM = r"(-?\d+(?:\.\d+)?)"


@dataclass
class Paso:
    """Un tramo del camino: una celda (lógica) o la red que sale de ella (ruteo)."""

    tipo: str  # "logica" o "ruteo"
    que: str  # tipo de celda (LUT6, CARRY4…) o "net (fo=N)"
    retardo: float
    nombre: str


@dataclass
class Camino:
    slack: float
    origen: str
    destino: str
    requerido: float
    retardo_datos: float
    logica: float
    ruteo: float
    niveles: str
    skew: float
    pasos: list[Paso] = field(default_factory=list)


def resumen_timing(texto: str) -> dict[str, float]:
    """WNS, TNS, endpoints que fallan, WHS y THS de "Design Timing Summary"."""
    m = re.search(r"WNS\(ns\)\s+TNS\(ns\).*\n\s*-+.*\n\s*(.+)", texto)
    if m is None:
        raise ValueError("no encontré la tabla Design Timing Summary")
    v = [float(x) for x in m.group(1).split()]
    return {
        "wns": v[0],
        "tns": v[1],
        "fallan_setup": v[2],
        "endpoints": v[3],
        "whs": v[4],
        "ths": v[5],
        "fallan_hold": v[6],
    }


def _pasos(bloque: str) -> list[Paso]:
    """Tramos del camino de datos: entre el FF de origen y el de destino."""
    lineas = bloque.splitlines()
    pasos = []
    for i, linea in enumerate(lineas):
        if "net (fo=" in linea:
            m = re.search(r"net \(fo=(\d+)[^)]*\)\s+" + _NUM + r"\s+" + _NUM + r"\s+(\S+)", linea)
            if m:
                pasos.append(Paso("ruteo", f"net (fo={m.group(1)})", float(m.group(2)), m.group(4)))
        elif "(Prop_" in linea:
            # A veces el retardo pasa a la línea siguiente (celdas con nombre de pin largo)
            texto = (
                linea
                if re.search(r"\)\s+" + _NUM + r"\s+" + _NUM, linea)
                else linea + lineas[i + 1]
            )
            m = re.search(
                r"(\w+) \(Prop_[^)]*\)\s+" + _NUM + r"\s+" + _NUM + r"\s+[rf]\s+(\S+)", texto
            )
            if m:
                pasos.append(Paso("logica", m.group(1), float(m.group(2)), m.group(4)))
    return pasos


def caminos(texto: str) -> list[Camino]:
    """Cada camino de un `report_timing`, con su desglose."""
    resultado = []
    for bloque in re.split(r"\n(?=Slack \()", texto)[1:]:

        def campo(patron: str, b: str = bloque) -> re.Match[str]:
            m = re.search(patron, b)
            if m is None:
                raise ValueError(f"camino sin {patron!r}")
            return m

        retardo = campo(
            r"Data Path Delay:\s+" + _NUM + r"ns\s+\(logic " + _NUM + r"ns.*route " + _NUM
        )
        separadores = [m.start() for m in re.finditer(r"\n\s+-{20,}", bloque)]
        datos = bloque[separadores[1] : separadores[2]] if len(separadores) >= 3 else ""
        resultado.append(
            Camino(
                slack=float(campo(r"Slack \(\w+\) :\s+" + _NUM).group(1)),
                origen=campo(r"Source:\s+(\S+)").group(1),
                destino=campo(r"Destination:\s+(\S+)").group(1),
                requerido=float(campo(r"Requirement:\s+" + _NUM).group(1)),
                retardo_datos=float(retardo.group(1)),
                logica=float(retardo.group(2)),
                ruteo=float(retardo.group(3)),
                niveles=campo(r"Logic Levels:\s+(.+)").group(1).strip(),
                skew=float(campo(r"Clock Path Skew:\s+" + _NUM).group(1)),
                pasos=_pasos(datos),
            )
        )
    return resultado


def tabla_util(texto: str) -> dict[str, tuple[str, str, str]]:
    """Fila → (usado, disponible, %) de las tablas de `report_utilization`."""
    filas: dict[str, tuple[str, str, str]] = {}
    for m in re.finditer(
        r"^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d*\s*\|\s*(\d*)\s*\|\s*([\d.<]*)\s*\|",
        texto,
        re.M,
    ):
        filas.setdefault(m.group(1), (m.group(2), m.group(3), m.group(4)))
    return filas


def jerarquia(texto: str) -> list[list[str]]:
    """Filas de "Utilization by Hierarchy": instancia (con su sangría), módulo y recursos."""
    filas = []
    for linea in texto.splitlines():
        celdas = linea.split("|")[1:-1]
        if len(celdas) >= 7 and celdas[2].strip().isdigit():
            nivel = (len(celdas[0]) - len(celdas[0].lstrip()) - 1) // 2
            filas.append(["  " * nivel + celdas[0].strip()] + [c.strip() for c in celdas[1:]])
    return filas


def potencia(texto: str) -> dict[str, str]:
    """Filas "| nombre | valor |" de `report_power` (total, dinámica, estática, componentes)."""
    return {
        m.group(1): m.group(2)
        for m in re.finditer(r"^\|\s*([^|]+?)\s*\|\s*([\d.<]+)\s*\|", texto, re.M)
    }


def barrido(texto: str) -> list[dict[str, str]]:
    return list(csv.DictReader(texto.splitlines()))


def optima(filas: list[dict[str, str]]) -> dict[str, str] | None:
    """La mayor frecuencia con WNS >= 0,3 ns y WHS >= 0 (ADR-016)."""
    buenas = [f for f in filas if float(f["wns_ns"]) >= MARGEN_WNS and float(f["whs_ns"]) >= 0]
    return max(buenas, key=lambda f: float(f["mhz"]), default=None)


def rendimiento(texto: str) -> list[dict[str, float | str]]:
    """Por programa: ciclos, instrucciones, CPI y ciclos perdidos (stalls y control).

    Perdidos = ciclos - instrucciones - 4 de llenado: lo que costaron los riesgos. Los stalls
    son los ciclos de load-use; el resto son burbujas de flush (saltos y branches tomados).
    """
    filas: list[dict[str, float | str]] = []
    for f in csv.DictReader(texto.splitlines()):
        if f["resultado"] != "OK":
            continue
        ciclos, instr, stalls = int(f["ciclos"]), int(f["instrucciones"]), int(f["stalls"])
        perdidos = ciclos - instr - LLENADO
        filas.append(
            {
                "programa": f["programa"],
                "ciclos": ciclos,
                "instrucciones": instr,
                "cpi": ciclos / instr,
                "stalls": stalls,
                "control": perdidos - stalls,
                "perdidos": perdidos,
            }
        )
    return filas


def _tabla(encabezado: list[str], filas: list[list[str]]) -> str:
    lineas = ["| " + " | ".join(encabezado) + " |", "|" + "---|" * len(encabezado)]
    lineas += ["| " + " | ".join(f) + " |" for f in filas]
    return "\n".join(lineas)


def _corto(nombre: str) -> str:
    return f"`{nombre}`"


def markdown(dir_reportes: Path) -> str:
    def leer(nombre: str) -> str | None:
        ruta = dir_reportes / nombre
        return ruta.read_text(encoding="utf-8", errors="replace") if ruta.exists() else None

    falta = "_Falta `{}`: correr `{}` desde TP3/._"
    partes = [
        "# Datos de Vivado del sistema completo",
        "",
        "Generado por `tools/scripts/resumen_reportes.py` desde "
        f"`{dir_reportes.parent.name}/{dir_reportes.name}/`. "
        "No editar a mano: volver a correr `make impl`, `make freq-sweep` y `make reportes`.",
    ]

    partes += ["", "## Resumen de timing (`top_timing_summary.rpt`)", ""]
    if (t := leer("top_timing_summary.rpt")) is not None:
        r = resumen_timing(t)
        partes.append(
            _tabla(
                [
                    "WNS (ns)",
                    "TNS (ns)",
                    "Endpoints que fallan (setup)",
                    "WHS (ns)",
                    "THS (ns)",
                    "Endpoints",
                ],
                [
                    [
                        f"{r['wns']:.3f}",
                        f"{r['tns']:.3f}",
                        f"{r['fallan_setup']:.0f}",
                        f"{r['whs']:.3f}",
                        f"{r['ths']:.3f}",
                        f"{r['endpoints']:.0f}",
                    ]
                ],
            )
        )
    else:
        partes.append(falta.format("top_timing_summary.rpt", "make impl"))

    for archivo, titulo in (("top_timing_setup.rpt", "setup"), ("top_timing_hold.rpt", "hold")):
        partes += ["", f"## Los 10 peores caminos de {titulo} (`{archivo}`)", ""]
        if (t := leer(archivo)) is None:
            partes.append(falta.format(archivo, "make impl"))
            continue
        cs = caminos(t)
        partes.append(
            _tabla(
                [
                    "#",
                    "Slack (ns)",
                    "Origen",
                    "Destino",
                    "Retardo (ns)",
                    "Lógica / ruteo",
                    "Niveles",
                    "Skew (ns)",
                ],
                [
                    [
                        str(i),
                        f"{c.slack:.3f}",
                        _corto(c.origen),
                        _corto(c.destino),
                        f"{c.retardo_datos:.3f}",
                        f"{c.logica / c.retardo_datos:.0%} / {c.ruteo / c.retardo_datos:.0%}"
                        if c.retardo_datos
                        else "-",
                        c.niveles,
                        f"{c.skew:.3f}",
                    ]
                    for i, c in enumerate(cs, 1)
                ],
            )
        )
        if titulo == "setup" and cs:
            peor = cs[0]
            partes += ["", "### El peor camino de setup, tramo por tramo", ""]
            partes.append(
                _tabla(
                    ["Tramo", "Tipo", "Retardo (ns)", "Celda o red"],
                    [[p.tipo, p.que, f"{p.retardo:.3f}", _corto(p.nombre)] for p in peor.pasos],
                )
            )
            partes += [
                "",
                f"Lógica: {peor.logica:.3f} ns · ruteo: {peor.ruteo:.3f} ns · "
                f"requerido: {peor.requerido:.3f} ns · skew: {peor.skew:.3f} ns",
            ]

    partes += ["", "## Barrido de frecuencia (`freq_sweep.csv`)", ""]
    if (t := leer("freq_sweep.csv")) is not None:
        filas = barrido(t)
        partes.append(
            _tabla(
                [
                    "MHz",
                    "Período (ns)",
                    "WNS (ns)",
                    "WHS (ns)",
                    "TNS (ns)",
                    f"Cumple (WNS ≥ {MARGEN_WNS}, WHS ≥ 0)",
                ],
                [
                    [f["mhz"], f["periodo_ns"], f["wns_ns"], f["whs_ns"], f["tns_ns"], f["cumple"]]
                    for f in filas
                ],
            )
        )
        mejor = optima(filas)
        partes += [
            "",
            f"Frecuencia óptima según ADR-016: **{mejor['mhz']} MHz**."
            if mejor
            else "Ninguna frecuencia del barrido cumple ADR-016.",
        ]
    else:
        partes.append(falta.format("freq_sweep.csv", "make freq-sweep"))

    partes += ["", "## Rendimiento (`docs/informe/datos/cpi.csv`)", ""]
    if CPI_CSV.exists():
        filas_r = rendimiento(CPI_CSV.read_text(encoding="utf-8"))
        sweep = leer("freq_sweep.csv")
        mejor_f = optima(barrido(sweep)) if sweep is not None else None
        mhz = float(mejor_f["mhz"]) if mejor_f else None
        encabezado = [
            "Programa",
            "Ciclos",
            "Instrucciones",
            "CPI",
            "Stalls",
            "Control",
            "% perdidos",
        ]
        if mhz:
            encabezado.append(f"Tiempo a {mhz:g} MHz (µs)")
        cuerpo = []
        for f in filas_r:
            fila = [
                str(f["programa"]),
                str(f["ciclos"]),
                str(f["instrucciones"]),
                f"{f['cpi']:.3f}",
                str(f["stalls"]),
                str(f["control"]),
                f"{100 * int(f['perdidos']) / int(f['ciclos']):.1f}",
            ]
            if mhz:
                fila.append(f"{int(f['ciclos']) / mhz:.2f}")
            cuerpo.append(fila)
        partes.append(_tabla(encabezado, cuerpo))
        ciclos_t = sum(int(f["ciclos"]) for f in filas_r)
        instr_t = sum(int(f["instrucciones"]) for f in filas_r)
        stalls_t = sum(int(f["stalls"]) for f in filas_r)
        control_t = sum(int(f["control"]) for f in filas_r)
        partes += [
            "",
            f"Total de {len(filas_r)} programas: {ciclos_t} ciclos, {instr_t} instrucciones, "
            f"CPI agregado {ciclos_t / instr_t:.3f}; ciclos perdidos por load-use {stalls_t} "
            f"({100 * stalls_t / ciclos_t:.1f} %), por control {control_t} "
            f"({100 * control_t / ciclos_t:.1f} %), llenado {LLENADO * len(filas_r)}.",
        ]
    else:
        partes.append("_Falta `docs/informe/datos/cpi.csv`: correr `make verify` desde TP3/._")

    partes += ["", "## Recursos (`top_util.rpt`)", ""]
    if (t := leer("top_util.rpt")) is not None:
        u = tabla_util(t)
        nombres = [
            "Slice LUTs",
            "LUT as Logic",
            "LUT as Memory",
            "Slice Registers",
            "F7 Muxes",
            "F8 Muxes",
            "Block RAM Tile",
            "DSPs",
            "Bonded IOB",
            "BUFGCTRL",
        ]
        partes.append(
            _tabla(["Recurso", "Usado", "Disponible", "%"], [[n, *u[n]] for n in nombres if n in u])
        )
    else:
        partes.append(falta.format("top_util.rpt", "make impl"))

    partes += ["", "## Recursos por módulo (`top_util_hier.rpt`)", ""]
    if (t := leer("top_util_hier.rpt")) is not None:
        filas_h = jerarquia(t)
        partes.append(
            _tabla(
                [
                    "Instancia",
                    "Módulo",
                    "LUTs",
                    "LUTs lógica",
                    "LUTRAM",
                    "SRL",
                    "FF",
                    "RAMB36",
                    "RAMB18",
                    "DSP",
                ],
                [[f"`{f[0]}`" if f[0].strip() else f[0], *f[1:10]] for f in filas_h],
            )
        )
    else:
        partes.append(falta.format("top_util_hier.rpt", "make impl"))

    partes += ["", "## Potencia (`top_power.rpt`)", ""]
    if (t := leer("top_power.rpt")) is not None:
        p = potencia(t)
        nombres = [
            "Total On-Chip Power (W)",
            "Dynamic (W)",
            "Device Static (W)",
            "Junction Temperature (C)",
            "Clocks",
            "Slice Logic",
            "Signals",
            "LUT as Distributed RAM",
            "I/O",
            "MMCM",
        ]
        partes.append(_tabla(["Concepto", "Valor"], [[n, p[n]] for n in nombres if n in p]))
        partes += [
            "",
            "Estimación vectorless de Vivado (sin actividad simulada): sirve para comparar, "
            "no como medición.",
        ]
    else:
        partes.append(falta.format("top_power.rpt", "make impl"))

    return "\n".join(partes) + "\n"


def main(argv: list[str] | None = None) -> None:
    """Sin argumentos, `hw/reports/` → `reportes_vivado.md`. Con `<carpeta> <salida.md>`, otra
    corrida guardada (por ejemplo `hw/reports/antes_100mhz/`, el sistema a 100 MHz sin MMCM)."""
    args = sys.argv[1:] if argv is None else argv
    origen, salida = (Path(args[0]), Path(args[1])) if len(args) == 2 else (REPORTES, SALIDA)
    texto = markdown(origen)
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(texto, encoding="utf-8")
    print(texto)
    print(f"Escrito en {salida}")


if __name__ == "__main__":
    main()
