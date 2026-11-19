"""Página Registros (US-504): los 32 en el formato elegido, lo que cambió en este paso (y quién
lo escribió) y lo que se escribe al final de este ciclo.

Dos tablas de 16 (x0…x15 y x16…x31) para que entren sin scroll. Se rearman en cada refresco:
cambia la cantidad de columnas con el formato.
"""

from collections.abc import Callable

import flet as ft

from riscv_toolkit.ui.arquitectura import FilaRegistro
from riscv_toolkit.ui.historial import CambioRegistro
from riscv_toolkit.ui.tema import FUENTE_CODIGO, tarjeta, titulo

COLOR_CAMBIO = ft.Colors.PRIMARY_CONTAINER  # el mismo que la línea en ejecución del listado
_POR_TABLA = 16
_FORMATOS = {
    "Hex": ("Hex",),
    "Con signo": ("Con signo",),
    "Sin signo": ("Sin signo",),
    "Los tres": ("Hex", "Con signo", "Sin signo"),
}


def _t(valor: str, negrita: bool = False, tenue: bool = False) -> ft.Text:
    return ft.Text(
        valor,
        font_family=FUENTE_CODIGO,
        size=13,
        weight=ft.FontWeight.W_600 if negrita else None,
        color=ft.Colors.ON_SURFACE_VARIANT if tenue else None,
    )


def _tabla(filas: list[FilaRegistro], columnas: tuple[str, ...]) -> ft.DataTable:
    def valor(f: FilaRegistro, col: str) -> str:
        return {"Hex": f.hexa, "Con signo": f.con_signo, "Sin signo": f.sin_signo}[col]

    return ft.DataTable(
        columns=[ft.DataColumn(label=t) for t in ("Reg", *columnas, "")],
        rows=[
            ft.DataRow(
                [
                    ft.DataCell(_t(f.nombre, negrita=True)),
                    *(ft.DataCell(_t(valor(f, c), negrita=f.cambio)) for c in columnas),
                    ft.DataCell(
                        _t(
                            "fijo en 0" if f.nombre == "x0" else "cambió" if f.cambio else "",
                            tenue=True,
                        )
                    ),
                ],
                color=COLOR_CAMBIO if f.cambio else None,
            )
            for f in filas
        ],
        heading_row_color=ft.Colors.SURFACE_CONTAINER_HIGHEST,
        data_row_min_height=26,
        data_row_max_height=26,
        heading_row_height=30,
        column_spacing=20,
    )


class VistaRegistros:
    def __init__(self, al_cambiar: Callable[[], None]) -> None:
        self.formato = ft.SegmentedButton(
            segments=[ft.Segment(n, label=n) for n in _FORMATOS],
            selected=["Los tres"],
            on_change=lambda _: al_cambiar(),
        )
        self._tablas = ft.Row(spacing=16, vertical_alignment=ft.CrossAxisAlignment.START)
        self._cambios = ft.Column(spacing=4)
        self._escribe = ft.Column(spacing=4)
        self.control = ft.Column(
            [
                ft.Row([titulo("Registros"), ft.Container(expand=True), self.formato]),
                ft.Row(
                    [
                        self._tablas,
                        ft.Column(
                            [
                                tarjeta(titulo("Cambió en este paso"), self._cambios),
                                tarjeta(titulo("Se escribe al final de este ciclo"), self._escribe),
                            ],
                            expand=True,
                        ),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.START,
                ),
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
        )

    def mostrar(
        self,
        filas: list[FilaRegistro],
        cambios: list[CambioRegistro],
        escribe: tuple[int, int, str] | None,
    ) -> None:
        columnas = _FORMATOS[self.formato.selected[0] if self.formato.selected else "Los tres"]
        self._tablas.controls = [
            _tabla(filas[i : i + _POR_TABLA], columnas) for i in range(0, 32, _POR_TABLA)
        ]
        self._cambios.controls = [
            ft.Column(
                [
                    _t(f"x{c.reg}: 0x{c.antes:x} → 0x{c.despues:x}", negrita=True),
                    ft.Text(
                        f"lo escribió {c.quien} (en WB en el ciclo {c.ciclo})"
                        if c.quien is not None
                        else "no se sabe qué instrucción (hubo un RUN, o el modo simulado)",
                        size=12,
                        color=ft.Colors.ON_SURFACE_VARIANT,
                    ),
                ],
                spacing=0,
            )
            for c in cambios
        ] or [ft.Text("Ningún registro cambió en este paso.", size=12)]
        if escribe is None:
            self._escribe.controls = [
                ft.Text(
                    "Nada: la instrucción en WB no escribe un registro (o es burbuja).", size=12
                )
            ]
        else:
            rd, valor, texto = escribe
            self._escribe.controls = [
                _t(f"x{rd} ← 0x{valor:x}", negrita=True),
                ft.Text(
                    f"{texto}, desde MEM/WB (según result_src)",
                    size=12,
                    color=ft.Colors.ON_SURFACE_VARIANT,
                ),
            ]
