"""Carta de pipeline (US-503): instrucciones en filas, ciclos en columnas.

Qué va en cada celda lo decide `ui/pipeline_chart.py`. Acá la grilla se rearma entera en cada
refresco (cambia de tamaño con cada paso), pero solo cuando la página está a la vista.
Mismos colores que la página Pipeline. La columna del ciclo que se está mirando va resaltada,
y tocar el número de un ciclo lleva a ese ciclo (mueve la línea de tiempo).
"""

from collections.abc import Callable

import flet as ft

from riscv_toolkit.ui.pipeline_chart import Carta, Celda, Fila
from riscv_toolkit.ui.tema import FUENTE_CODIGO, RIESGO, chip, rayado

_ANCHO_CELDA = 44
_ANCHO_INSTR = 230
_ALTO = 24
MAX_CICLOS = 80  # shortcut: solo los últimos 80 snapshots; paginar si hace falta ver más


def _texto(valor: str, ancho: int, *, tenue: bool = False, tachado: bool = False) -> ft.Container:
    return ft.Container(
        ft.Text(
            valor,
            size=12,
            font_family=FUENTE_CODIGO,
            no_wrap=True,
            italic=tenue,
            color=ft.Colors.ON_SURFACE_VARIANT if tenue or tachado else None,
            style=ft.TextStyle(decoration=ft.TextDecoration.LINE_THROUGH) if tachado else None,
        ),
        width=ancho,
        height=_ALTO,
        alignment=ft.Alignment.CENTER_LEFT,
    )


def _celda(c: Celda | None, fila: Fila, actual: bool) -> ft.Container:
    """`c` None: la "✕" del ciclo siguiente a un flush (la instrucción ya no está)."""
    caja = ft.Container(
        width=_ANCHO_CELDA,
        height=_ALTO,
        alignment=ft.Alignment.CENTER,
        border=ft.Border.all(
            2 if actual else 1, ft.Colors.PRIMARY if actual else ft.Colors.SURFACE
        ),
    )
    if c is None:
        caja.content = ft.Text("✕", size=12, color=RIESGO["fl"][0])
        return caja
    color: ft.ColorValue | None = None
    fondo: ft.ColorValue | None = ft.Colors.SURFACE_CONTAINER_HIGHEST
    if fila.pc is None:
        caja.gradient, fondo = rayado(), None
    elif fila.halt:
        color, fondo = RIESGO["ht"]
    if c.fwd:
        color, fondo = RIESGO["fa" if "A" in c.fwd else "fb"]
    if c.congelada:
        color, fondo = RIESGO["st"]
    if c.anulada:
        color, fondo = RIESGO["fl"]
    caja.bgcolor = fondo
    caja.content = ft.Text(
        spans=[
            ft.TextSpan(c.etapa),
            ft.TextSpan(c.fwd, style=ft.TextStyle(size=8, weight=ft.FontWeight.W_700)),
        ],
        size=11,
        font_family=FUENTE_CODIGO,
        color=color,
        italic=fila.pc is None,
        style=ft.TextStyle(decoration=ft.TextDecoration.LINE_THROUGH) if c.anulada else None,
    )
    return caja


class VistaCarta:
    """Leyenda y aviso arriba, y la grilla con scroll en los dos ejes."""

    def __init__(self, al_ir: Callable[[int], None]) -> None:
        """`al_ir(indice)`: clic en un ciclo; el índice es del historial entero."""
        self._al_ir = al_ir
        self._aviso = ft.Text(size=12, color=ft.Colors.ON_SURFACE_VARIANT)
        self._grilla = ft.Stack()
        leyenda = ft.Row(
            [
                chip("stall", "st"),
                chip("flush", "fl"),
                chip("forwarding A", "fa"),
                chip("forwarding B", "fb"),
                ft.Container(
                    ft.Text("burbuja", size=11),
                    gradient=rayado(),
                    border_radius=4,
                    padding=ft.Padding.symmetric(horizontal=6, vertical=1),
                ),
                chip("HALT", "ht"),
                ft.Text("Tocá un ciclo para ir a él.", size=12, color=ft.Colors.ON_SURFACE_VARIANT),
            ],
            spacing=6,
            wrap=True,
        )
        self.control = ft.Column(
            [
                leyenda,
                self._aviso,
                ft.Row(
                    [self._grilla],
                    scroll=ft.ScrollMode.AUTO,
                    vertical_alignment=ft.CrossAxisAlignment.START,
                ),
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
        )

    def mostrar(self, carta: Carta | None, cursor: int | None = None, desde: int = 0) -> None:
        """`cursor`: la columna del ciclo que se está mirando. `desde`: el índice en el
        historial de la primera columna (se muestran solo las últimas MAX_CICLOS)."""
        if carta is None or not carta.ciclos:
            self._aviso.value = "Sin historial: cargá un programa y avanzá con Paso."
            self._grilla.controls = []
            return
        self._aviso.value = (
            "Solo paso a paso: un RUN trae únicamente el estado final, así que la carta "
            "se corta donde hubo un salto de ciclos."
            if not carta.completa
            else f"{len(carta.filas)} instrucciones · {len(carta.ciclos)} ciclos"
        )
        ciclos: list[ft.Control] = []
        for t, n in enumerate(carta.ciclos):
            actual = t == cursor
            ciclos.append(
                ft.Container(
                    ft.Text(
                        str(n),
                        size=12,
                        weight=ft.FontWeight.W_600,
                        font_family=FUENTE_CODIGO,
                        color=ft.Colors.ON_PRIMARY if actual else None,
                    ),
                    width=_ANCHO_CELDA,
                    height=_ALTO,
                    alignment=ft.Alignment.CENTER,
                    bgcolor=ft.Colors.PRIMARY if actual else None,
                    on_click=lambda _, t=t: self._al_ir(desde + t),
                    tooltip=f"Ir al ciclo {n}",
                )
            )
        encabezado = ft.Container(
            ft.Row([_texto("Instrucción", _ANCHO_INSTR), *ciclos], spacing=0),
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
        )
        filas: list[ft.Control] = [encabezado]
        for f in carta.filas:
            etiqueta = "burbuja" if f.pc is None else f"0x{f.pc:03x}  {f.texto}"
            # Un espaciador hasta el primer ciclo y solo las celdas de su tramo (~5): con
            # una celda por ciclo la grilla tendría filas por ciclos controles.
            primero, ultimo = min(f.celdas), max(f.celdas)
            if f.anulada and ultimo + 1 < len(carta.ciclos):
                ultimo += 1  # la "✕": el ciclo en que ya no está
            filas.append(
                ft.Row(
                    [
                        _texto(etiqueta, _ANCHO_INSTR, tenue=f.pc is None, tachado=f.anulada),
                        ft.Container(width=primero * _ANCHO_CELDA),
                        *(
                            _celda(f.celdas.get(t), f, t == cursor)
                            for t in range(primero, ultimo + 1)
                        ),
                    ],
                    spacing=0,
                )
            )
        fondo: list[ft.Control] = []
        if cursor is not None and 0 <= cursor < len(carta.ciclos):
            # La columna del ciclo, también donde no hay celdas (debajo de la grilla).
            fondo.append(
                ft.Container(
                    left=_ANCHO_INSTR + cursor * _ANCHO_CELDA,
                    top=0,
                    bottom=0,
                    width=_ANCHO_CELDA,
                    bgcolor=ft.Colors.PRIMARY_CONTAINER,
                )
            )
        self._grilla.controls = [*fondo, ft.Column(filas, spacing=0)]
