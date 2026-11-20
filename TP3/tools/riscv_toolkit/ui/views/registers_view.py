"""Página Registros (US-504): los 32 en el formato elegido, lo que cambió en este paso (y quién
lo escribió) y lo que se escribe al final de este ciclo.

Arriba, las dos tarjetas de lo que pasó en el ciclo; abajo, dos tablas de 16 (x0…x15 y
x16…x31) que se estiran a lo ancho. Son filas armadas a mano y no un `DataTable`: el de
Flutter no estira sus columnas y dejaba media pantalla vacía. Se rearman en cada refresco
porque cambia la cantidad de columnas con el formato.
"""

from collections.abc import Callable

import flet as ft

from riscv_toolkit.ui.arquitectura import FilaRegistro
from riscv_toolkit.ui.historial import CambioRegistro
from riscv_toolkit.ui.tema import FUENTE_CODIGO, LETRA_NOTA, LETRA_TABLA, tarjeta, titulo

COLOR_CAMBIO = ft.Colors.PRIMARY_CONTAINER  # el mismo que la línea en ejecución del listado
_POR_TABLA = 16
_ALTO_FILA = 25  # 16 filas + encabezado + tarjetas entran en 768 de alto
_ANCHO_NOMBRE = 56
_FORMATOS = {
    "Hex": ("Hex",),
    "Con signo": ("Con signo",),
    "Sin signo": ("Sin signo",),
    "Los tres": ("Hex", "Con signo", "Sin signo"),
}


def _t(valor: str, negrita: bool = False, tenue: bool = False, **kw: object) -> ft.Text:
    return ft.Text(
        valor,
        font_family=FUENTE_CODIGO,
        size=LETRA_TABLA,
        weight=ft.FontWeight.W_600 if negrita else None,
        color=ft.Colors.ON_SURFACE_VARIANT if tenue else None,
        no_wrap=True,
        **kw,  # type: ignore[arg-type]
    )


def _fila(celdas: list[ft.Control], **kw: object) -> ft.Container:
    return ft.Container(
        ft.Row(celdas, spacing=12),
        height=_ALTO_FILA,
        padding=ft.Padding.symmetric(horizontal=10),
        alignment=ft.Alignment.CENTER_LEFT,
        **kw,  # type: ignore[arg-type]
    )


def _tabla(filas: list[FilaRegistro], columnas: tuple[str, ...]) -> ft.Container:
    def valor(f: FilaRegistro, col: str) -> str:
        return {"Hex": f.hexa, "Con signo": f.con_signo, "Sin signo": f.sin_signo}[col]

    encabezado = _fila(
        [
            ft.Text("Reg", weight=ft.FontWeight.W_600, size=LETRA_TABLA, width=_ANCHO_NOMBRE),
            *(
                ft.Text(c, weight=ft.FontWeight.W_600, size=LETRA_TABLA, expand=True)
                for c in columnas
            ),
        ],
        bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
    )
    cuerpo = [
        _fila(
            [
                _t(f.nombre, negrita=True, width=_ANCHO_NOMBRE),
                *(_t(valor(f, c), negrita=f.cambio, expand=True) for c in columnas),
            ],
            bgcolor=COLOR_CAMBIO if f.cambio else None,
            tooltip="x0 vale siempre 0"
            if f.nombre == "x0"
            else "Cambió en este paso"
            if f.cambio
            else None,
        )
        for f in filas
    ]
    return ft.Container(
        ft.Column([encabezado, *cuerpo], spacing=0),
        expand=True,
        border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
        border_radius=6,
        clip_behavior=ft.ClipBehavior.HARD_EDGE,
    )


def _nota(texto: str) -> ft.Text:
    return ft.Text(texto, size=LETRA_NOTA, color=ft.Colors.ON_SURFACE_VARIANT)


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
                        tarjeta(titulo("Cambió en este paso"), self._cambios, expand=True),
                        tarjeta(
                            titulo("Se escribe al final de este ciclo"), self._escribe, expand=True
                        ),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.START,
                ),
                self._tablas,
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
            ft.Row(
                [
                    _t(f"x{c.reg}: 0x{c.antes:x} → 0x{c.despues:x}", negrita=True),
                    _nota(
                        f"lo escribió {c.quien} (en WB en el ciclo {c.ciclo})"
                        if c.quien is not None
                        else "no se sabe qué instrucción (hubo un RUN, o el modo simulado)"
                    ),
                ],
                spacing=10,
                wrap=True,
            )
            for c in cambios
        ] or [_nota("Ningún registro cambió en este paso.")]
        if escribe is None:
            self._escribe.controls = [
                _nota("Nada: la instrucción en WB no escribe un registro (o es burbuja).")
            ]
        else:
            rd, valor, texto = escribe
            self._escribe.controls = [
                ft.Row(
                    [
                        _t(f"x{rd} ← 0x{valor:x}", negrita=True),
                        _nota(f"{texto}, desde MEM/WB (según result_src)"),
                    ],
                    spacing=10,
                    wrap=True,
                )
            ]
