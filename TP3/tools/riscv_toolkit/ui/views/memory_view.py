"""Página Memoria (US-504): la usada por el programa (con quién escribió cada palabra) y,
aparte, un rango leído a pedido con DUMP_MEM (AC3).

Cada palabra: dirección, hex, sus 4 bytes en orden de dirección (little-endian: +0 es el
menos significativo) y ASCII. Se resalta la fila que cambió y, adentro, el byte que cambió
(AC2: un `sb`). Las filas cambian de cantidad, así que la tabla se rearma en cada refresco.
"""

from collections.abc import Awaitable, Callable

import flet as ft

from riscv_toolkit.protocol.comandos import DMEM_DEPTH
from riscv_toolkit.ui.arquitectura import FilaMemoria
from riscv_toolkit.ui.tema import FUENTE_CODIGO, chip, tarjeta, titulo
from riscv_toolkit.ui.views.registers_view import COLOR_CAMBIO


def _texto(valor: str, destacado: bool = False, tenue: bool = False) -> ft.Text:
    return ft.Text(
        valor,
        font_family=FUENTE_CODIGO,
        size=13,
        color=ft.Colors.ON_PRIMARY
        if destacado
        else ft.Colors.ON_SURFACE_VARIANT
        if tenue
        else None,
        weight=ft.FontWeight.W_600 if destacado else None,
    )


def _byte(valor: str, cambio: bool) -> ft.Control:
    if not cambio:
        return _texto(valor)
    return ft.Container(  # el byte que cambió, con relleno fuerte dentro de la fila resaltada
        _texto(valor, destacado=True),
        bgcolor=ft.Colors.PRIMARY,
        border_radius=3,
        padding=ft.Padding.symmetric(horizontal=3),
    )


def _tabla(con_escritura: bool) -> ft.DataTable:
    columnas = ["Dirección", "Hex", "+0", "+1", "+2", "+3", "ASCII"]
    if con_escritura:
        columnas.append("Última escritura")
    return ft.DataTable(
        columns=[ft.DataColumn(label=t) for t in columnas],
        heading_row_color=ft.Colors.SURFACE_CONTAINER_HIGHEST,
        data_row_min_height=26,
        data_row_max_height=26,
        heading_row_height=30,
        column_spacing=18,
    )


def _llenar(
    tabla: ft.DataTable, filas: list[FilaMemoria], escrituras: dict[int, str] | None = None
) -> None:
    """`escrituras`: dirección → quién la escribió (None: la tabla no tiene esa columna)."""
    tabla.rows = [
        ft.DataRow(
            [
                ft.DataCell(_texto(f.direccion)),
                ft.DataCell(_texto(f.hexa)),
                *(
                    ft.DataCell(_byte(b, c))
                    for b, c in zip(f.bytes_, f.bytes_cambiados, strict=True)
                ),
                ft.DataCell(_texto(f.ascii)),
                *(
                    [ft.DataCell(_texto(escrituras.get(int(f.direccion, 16), "—"), tenue=True))]
                    if escrituras is not None
                    else []
                ),
            ],
            color=COLOR_CAMBIO if f.cambio else None,
        )
        for f in filas
    ]


class VistaMemoria:
    def __init__(self, al_leer: Callable[[], Awaitable[None]]) -> None:
        """`al_leer`: el botón Leer (pide el rango con `DUMP_MEM`, en app.py)."""
        self._usadas = ft.Text(size=12)
        self._barra = ft.ProgressBar(value=0, width=200)
        self._usada = _tabla(con_escritura=True)
        self._vacia = ft.Text("El programa todavía no escribió la memoria.", size=12, italic=True)
        self.desde = ft.TextField(value="0x0", label="Desde", width=110, dense=True)
        self.hasta = ft.TextField(value="0x1c", label="Hasta", width=110, dense=True)
        self.leer = ft.OutlinedButton(
            "Leer", icon=ft.Icons.DOWNLOAD, on_click=al_leer, tooltip="DUMP_MEM (no ejecuta nada)"
        )
        self._chip = ft.Row()
        self._nota_pedido = ft.Text(size=12, color=ft.Colors.ON_SURFACE_VARIANT)
        self._pedido = _tabla(con_escritura=False)
        self.control = ft.Column(
            [
                ft.Row(
                    [titulo("Memoria usada"), ft.Container(expand=True), self._usadas, self._barra],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Text(
                    "Little-endian: el byte +0 es el menos significativo de la palabra (el que "
                    "escribe un sb a esa dirección).",
                    size=12,
                    color=ft.Colors.ON_SURFACE_VARIANT,
                ),
                self._vacia,
                self._usada,
                tarjeta(
                    ft.Row([titulo("Leer un rango"), self._chip]),
                    ft.Row(
                        [self.desde, self.hasta, self.leer],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    self._nota_pedido,
                    self._pedido,
                ),
            ],
            spacing=8,
            scroll=ft.ScrollMode.AUTO,
            expand=True,
        )

    def mostrar(
        self,
        usada: list[FilaMemoria],
        escrituras: dict[int, str],
        pedido: tuple[int, list[FilaMemoria]] | None,
    ) -> None:
        """`pedido`: (ciclo en que se leyó, filas), o None si no se pidió nada."""
        _llenar(self._usada, usada, escrituras)
        self._vacia.visible = not usada
        self._usada.visible = bool(usada)
        self._usadas.value = f"{len(usada)} de {DMEM_DEPTH} palabras usadas"
        self._barra.value = len(usada) / DMEM_DEPTH
        if pedido is None:
            self._chip.controls = []
            self._nota_pedido.value = "Pedí un rango de la DMEM con DUMP_MEM (no ejecuta nada)."
            self._pedido.visible = False
        else:
            ciclo, filas = pedido
            self._chip.controls = [chip(f"Leído a pedido · ciclo {ciclo}", "ht")]
            self._nota_pedido.value = "No se actualiza solo: volvé a leer después de ejecutar."
            _llenar(self._pedido, filas)
            self._pedido.visible = True
