"""Página Pipeline (US-502): tres vistas, Etapas | Latches | Campos.

- **Etapas:** las 5 etapas con los latches entre ellas (se tocan para ver uno), los colores de
  cada marca, las flechas de forwarding, "Qué pasó en este ciclo" y el latch elegido.
- **Latches:** los 4 latches juntos, agrupados en Datos / Control / Depuración.
- **Campos:** qué es cada campo, por qué viaja y quién lo usa (`ui/latch_info.py`).

Qué va en cada etapa lo decide `ui/pipeline.py`; acá solo se pinta. Las tarjetas se crean una
vez y se les cambian las propiedades; las tablas de latches (chicas) se rearman.
"""

from collections.abc import Callable
from typing import cast

import flet as ft

from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.ui.latch_info import CAMPOS, GRUPOS
from riscv_toolkit.ui.pipeline import (
    ETAPAS,
    LATCHES,
    Columna,
    campos_latch,
    destino_salto,
    explicar,
    latches,
    senales,
)
from riscv_toolkit.ui.tema import (
    FUENTE_CODIGO,
    LETRA_INSTR,
    LETRA_NOTA,
    LETRA_TABLA,
    RIESGO,
    chip,
    rayado,
    tarjeta,
    titulo,
)

# De dónde sale la instrucción de cada etapa (el snapshot no tiene un latch antes de IF).
_ORIGEN = {
    "IF": "PC → imagen",
    "ID": "IF/ID.instr",
    "EX": "ID/EX.instr",
    "MEM": "EX/MEM.instr",
    "WB": "MEM/WB.instr",
}
_OPERANDO = {"A": "fa", "B": "fb"}


def _texto(valor: str, size: int = LETRA_TABLA, **kw: object) -> ft.Text:
    return ft.Text(valor, font_family=FUENTE_CODIGO, size=size, **kw)  # type: ignore[arg-type]


class _Tarjeta:
    """Una etapa: nombre, de dónde sale, PC, instrucción, palabra y marcas."""

    def __init__(self, etapa: str) -> None:
        self.etapa = etapa
        self.pc = _texto("", 14, color=ft.Colors.ON_SURFACE_VARIANT)
        self.texto = _texto("", LETRA_INSTR, no_wrap=True)
        self.palabra = _texto("", LETRA_NOTA, color=ft.Colors.ON_SURFACE_VARIANT)
        self.marcas = ft.Row(spacing=4, wrap=True)
        self.control = ft.Container(
            ft.Column(
                [
                    ft.Row(
                        [
                            ft.Text(etapa, weight=ft.FontWeight.W_600, size=18),
                            ft.Text(
                                _ORIGEN[etapa],
                                size=LETRA_NOTA - 1,
                                color=ft.Colors.ON_SURFACE_VARIANT,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    self.pc,
                    self.texto,
                    self.palabra,
                    self.marcas,
                ],
                spacing=3,
            ),
            expand=True,
            height=170,
            padding=10,
            border_radius=8,
        )

    def mostrar(self, c: Columna, destino: int | None, salta: bool) -> None:
        """`salta`: esta etapa provoca el flush del ciclo; `destino`, a dónde."""
        borde: ft.ColorValue = ft.Colors.OUTLINE_VARIANT
        ancho = 1
        fondo: ft.ColorValue | None
        self.control.gradient = None
        chips: list[ft.Control] = []
        if c.burbuja:
            self.pc.value, self.palabra.value = "", "valid = 0"
            self.texto.value = "burbuja"
            self.texto.italic, self.texto.color = True, ft.Colors.ON_SURFACE_VARIANT
            self.control.gradient, fondo = rayado(), None
        else:
            self.pc.value = f"0x{c.pc:08x}" if c.pc is not None else ""
            self.palabra.value = f"{c.palabra:08x}" if c.palabra is not None else ""
            self.texto.value, self.texto.italic = c.texto, False
            self.texto.color = RIESGO["fl"][0] if c.ilegal else None
            fondo = ft.Colors.SURFACE_CONTAINER_HIGH
            if c.halt:
                fondo = RIESGO["ht"][1]
                chips.append(chip("HALT", "ht"))
            if c.ilegal:
                fondo = RIESGO["fl"][1]
                chips.append(chip("ILEGAL", "fl"))
        if c.congelada:
            fondo = RIESGO["st"][1]
            chips.append(chip("se congela", "st"))
        if c.anulada:
            fondo = RIESGO["fl"][1]
            chips.append(chip("flush", "fl"))
        if salta:
            hacia = f" → 0x{destino:03x}" if destino is not None else ""
            chips.append(
                ft.Container(
                    _texto(f"tomado{hacia}", 11, weight=ft.FontWeight.W_600),
                    bgcolor=ft.Colors.PRIMARY_CONTAINER,
                    border_radius=4,
                    padding=ft.Padding.symmetric(horizontal=6, vertical=1),
                )
            )
        for m in c.marcas:  # "A ← EX/MEM" en EX; "→ A" en la etapa fuente
            operando = m[0] if "←" in m else m[-1]
            chips.append(chip(m, _OPERANDO[operando]))
            if "→" in m:
                borde, ancho = RIESGO[_OPERANDO[operando]][0], 2
        self.texto.style = ft.TextStyle(
            decoration=ft.TextDecoration.LINE_THROUGH if c.anulada else ft.TextDecoration.NONE
        )
        self.control.bgcolor = fondo
        self.control.border = ft.Border.all(ancho, borde)
        self.marcas.controls = chips


def _franja(nombre: str, al_tocar: Callable[[str], None]) -> ft.Container:
    """Un latch entre dos etapas: una franja vertical que se toca para verlo."""
    return ft.Container(
        # Una letra por renglón: rotado, Flet lo recorta al ancho de la franja ("EX/M").
        ft.Text(
            "\n".join(nombre),
            size=13,
            weight=ft.FontWeight.W_600,
            text_align=ft.TextAlign.CENTER,
            style=ft.TextStyle(height=1.0),
        ),
        width=28,
        height=170,
        border_radius=6,
        alignment=ft.Alignment.CENTER,
        on_click=lambda _: al_tocar(nombre),
        tooltip=f"Ver el latch {nombre}",
    )


def tabla_latch(nombre: str, snapshot: Snapshot | None, viejos: set[str]) -> ft.Control:
    """Los campos de un latch agrupados en Datos / Control / Depuración: campo·bits, hex, dec.

    `viejos`: campos cuyo valor no se usa porque lo reemplaza el forwarding.
    """
    valores = {c: (h, d) for c, h, d in campos_latch(latches(snapshot)[nombre])}
    filas: list[ft.Control] = []
    for grupo in GRUPOS:
        campos = [c for c in CAMPOS[nombre] if c.grupo == grupo]
        if not campos:
            continue
        filas.append(
            ft.Text(
                grupo,
                size=LETRA_NOTA,
                weight=ft.FontWeight.W_600,
                color=ft.Colors.ON_SURFACE_VARIANT,
            )
        )
        for c in campos:
            hexa, dec = valores[c.nombre]
            viejo = c.nombre in viejos
            filas.append(
                ft.Container(
                    ft.Row(
                        [
                            ft.Row(
                                [
                                    _texto(c.nombre),
                                    _texto(f"·{c.bits}", 11, color=ft.Colors.ON_SURFACE_VARIANT),
                                ],
                                spacing=2,
                                width=150,
                            ),
                            _texto(hexa, width=118),
                            _texto(dec, expand=True, no_wrap=True),
                        ],
                        spacing=6,
                    ),
                    bgcolor=RIESGO["st"][1] if viejo else None,
                    tooltip="Valor viejo: lo reemplaza el forwarding" if viejo else None,
                    padding=ft.Padding.symmetric(horizontal=4),
                )
            )
    return ft.Column(filas, spacing=1)


def _viejos(snapshot: Snapshot | None) -> set[str]:
    """Los operandos de ID/EX que EX no usa porque llegan por forwarding."""
    if snapshot is None:
        return set()
    r = snapshot.riesgos
    return {campo for campo, fwd in (("rs1_data", r.fwd_a), ("rs2_data", r.fwd_b)) if fwd}


class VistaEtapas:
    def __init__(self, al_cambiar: Callable[[], None]) -> None:
        self.elegido = "ID/EX"
        self._tarjetas = {e: _Tarjeta(e) for e in ETAPAS}
        self._franjas = {n: _franja(n, self.elegir) for n in LATCHES}
        fila: list[ft.Control] = []
        for etapa, latch in zip(ETAPAS, [*LATCHES, None], strict=True):
            fila.append(self._tarjetas[etapa].control)
            if latch is not None:
                fila.append(self._franjas[latch])
        self._flechas = ft.Column(spacing=2)
        self._frases = ft.Column(spacing=6)
        self._senales = ft.Row(spacing=6, wrap=True)
        self._titulo_latch = titulo("")
        self._latch = ft.Column()
        self._al_cambiar = al_cambiar
        self.control = ft.Column(
            [
                ft.Row(fila, spacing=4),
                self._flechas,
                ft.Row(
                    [
                        tarjeta(
                            titulo("Qué pasó en este ciclo"), self._frases, self._senales, expand=3
                        ),
                        tarjeta(self._titulo_latch, self._latch, expand=2),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.START,
                ),
            ],
            spacing=10,
        )

    def elegir(self, nombre: str) -> None:
        self.elegido = nombre
        self._al_cambiar()

    def mostrar(self, snapshot: Snapshot | None, columnas: list[Columna] | None) -> None:
        cols = columnas or [Columna(e) for e in ETAPAS]
        destino = destino_salto(snapshot) if snapshot is not None else None
        r = snapshot.riesgos if snapshot is not None else None
        for c in cols:
            salta = r is not None and (
                (c.etapa == "EX" and r.flush_id_ex)
                or (c.etapa == "ID" and r.flush_if_id and not r.flush_id_ex)
            )
            self._tarjetas[c.etapa].mostrar(c, destino, salta)
        for nombre, franja in self._franjas.items():
            elegida = nombre == self.elegido
            franja.bgcolor = ft.Colors.PRIMARY if elegida else ft.Colors.SURFACE_CONTAINER_HIGHEST
            cast(ft.Text, franja.content).color = ft.Colors.ON_PRIMARY if elegida else None
        # Flechas de forwarding: "A ← EX/MEM (addi x1, x0, 5)".
        por_etapa = {c.etapa: c for c in cols}
        flechas: list[ft.Control] = []
        for m in por_etapa["EX"].marcas:
            operando, latch = m[0], m.split("← ")[1]
            fuente = por_etapa["MEM" if latch == "EX/MEM" else "WB"]
            color = RIESGO[_OPERANDO[operando]][0]
            flechas.append(
                ft.Row(
                    [
                        ft.Icon(ft.Icons.SUBDIRECTORY_ARROW_LEFT, color=color, size=16),
                        _texto(f"{operando} ← {latch} ({fuente.texto})", 14, color=color),
                    ],
                    spacing=4,
                )
            )
        self._flechas.controls = flechas
        if snapshot is None:
            self._frases.controls = [ft.Text("Sin snapshot: conectá y cargá un programa.")]
            self._senales.controls = []
        else:
            self._frases.controls = [ft.Text(f, size=LETRA_TABLA) for f in explicar(snapshot, cols)]
            self._senales.controls = [
                chip(texto, None, punteado=not activa) if not activa else chip(texto, "st")
                for texto, activa in senales(snapshot)
            ]
        self._titulo_latch.value = f"Latch {self.elegido}"
        self._latch.controls = [tabla_latch(self.elegido, snapshot, _viejos(snapshot))]


class VistaLatches:
    """Los 4 latches juntos: IF/ID y MEM/WB | ID/EX | EX/MEM."""

    def __init__(self) -> None:
        self._cajas = {n: ft.Column() for n in LATCHES}
        caja = self._cajas

        def columna(*nombres: str) -> ft.Container:
            controles: list[ft.Control] = []
            for n in nombres:
                controles += [titulo(n), caja[n]]
            return tarjeta(*controles, expand=True)

        self.control = ft.Row(
            [columna("IF/ID", "MEM/WB"), columna("ID/EX"), columna("EX/MEM")],
            vertical_alignment=ft.CrossAxisAlignment.START,
        )

    def mostrar(self, snapshot: Snapshot | None) -> None:
        for nombre, caja in self._cajas.items():
            viejos = _viejos(snapshot) if nombre == "ID/EX" else set()
            caja.controls = [tabla_latch(nombre, snapshot, viejos)]


def _vista_campos() -> ft.Control:
    """Qué es cada campo: estático, se arma una vez."""
    tarjetas: list[ft.Control] = [
        ft.Text(
            "Cada latch guarda lo que la etapa siguiente necesita de la anterior. Un campo viaja "
            "hasta la última etapa que lo usa: por eso rd llega a WB y imm no pasa de EX. "
            "instr viaja solo para la Debug Unit.",
            size=LETRA_TABLA,
        )
    ]
    for nombre in LATCHES:
        filas = [
            ft.DataRow(
                [
                    ft.DataCell(_texto(f"{c.nombre}·{c.bits}", 14)),
                    ft.DataCell(ft.Text(c.que, size=14)),
                    ft.DataCell(ft.Text(c.por_que, size=14)),
                    ft.DataCell(ft.Text(c.quien, size=14)),
                ]
            )
            for c in CAMPOS[nombre]
        ]
        tarjetas.append(
            tarjeta(
                titulo(nombre),
                ft.DataTable(
                    columns=[
                        ft.DataColumn(
                            label=ft.Text(t, size=LETRA_TABLA, weight=ft.FontWeight.W_600)
                        )
                        for t in ("Campo", "Qué es", "Por qué viaja", "Quién lo usa")
                    ],
                    rows=filas,
                    heading_row_color=ft.Colors.SURFACE_CONTAINER_HIGHEST,
                    data_row_min_height=32,
                    data_row_max_height=float("inf"),
                    heading_row_height=34,
                    column_spacing=16,
                ),
            )
        )
    return ft.Column(tarjetas, spacing=12)


class PaginaPipeline:
    """El selector Etapas | Latches | Campos y las tres vistas."""

    def __init__(self, al_cambiar: Callable[[], None]) -> None:
        """`al_cambiar`: se eligió otra vista u otro latch (app.py refresca)."""
        self.etapas = VistaEtapas(al_cambiar)
        self.latches = VistaLatches()
        self._campos = _vista_campos()
        self.selector = ft.SegmentedButton(
            segments=[ft.Segment(n, label=n) for n in ("Etapas", "Latches", "Campos")],
            selected=["Etapas"],
            on_change=lambda _: al_cambiar(),
        )
        leyenda = ft.Row(
            [
                chip("stall", "st"),
                chip("flush", "fl"),
                chip("forwarding A", "fa"),
                chip("forwarding B", "fb"),
                chip("HALT", "ht"),
                ft.Container(
                    ft.Text("burbuja", size=12),
                    gradient=rayado(),
                    border_radius=4,
                    padding=ft.Padding.symmetric(horizontal=6, vertical=1),
                ),
            ],
            spacing=6,
        )
        self.control = ft.Column(
            [
                ft.Row([self.selector, ft.Container(expand=True), leyenda]),
                self.etapas.control,
                self.latches.control,
                self._campos,
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=12,
        )

    def vista(self) -> str:
        return self.selector.selected[0] if self.selector.selected else "Etapas"

    def mostrar(self, snapshot: Snapshot | None, columnas: list[Columna] | None) -> None:
        vista = self.vista()
        self.etapas.control.visible = vista == "Etapas"
        self.latches.control.visible = vista == "Latches"
        self._campos.visible = vista == "Campos"
        if vista == "Etapas":
            self.etapas.mostrar(snapshot, columnas)
        elif vista == "Latches":
            self.latches.mostrar(snapshot)
