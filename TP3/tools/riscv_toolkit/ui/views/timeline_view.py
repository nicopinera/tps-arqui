"""Página Historial (US-505): la línea de tiempo con los eventos de cada ciclo, una tabla por
ciclo, y exportar o abrir una sesión.

Mover el cursor no le pide nada a la placa: el hardware no retrocede. Todas las vistas
muestran el snapshot bajo el cursor (AC1); el próximo Paso sigue desde el último y vuelve ahí.
"""

from collections.abc import Awaitable, Callable

import flet as ft

from riscv_toolkit.ui.historial import FilaHistorial
from riscv_toolkit.ui.tema import FUENTE_CODIGO, NOMBRE_RIESGO, RIESGO, chip, tarjeta, titulo

MAX_FILAS = (
    300  # shortcut: solo los últimos 300 ciclos en la tabla y la línea; paginar si hace falta
)
_ANCHOS = (60, 70, 300, 200)  # ciclo, PC, etapas, riesgos; los cambios se estiran


def _t(valor: str, ancho: int | None = None, tenue: bool = False) -> ft.Text:
    return ft.Text(
        valor,
        font_family=FUENTE_CODIGO,
        size=12,
        width=ancho,
        no_wrap=True,
        color=ft.Colors.ON_SURFACE_VARIANT if tenue else None,
    )


class VistaHistorial:
    def __init__(
        self,
        al_ir: Callable[[int], None],
        al_exportar: Callable[[], Awaitable[None]],
        al_reabrir: Callable[[], Awaitable[None]],
    ) -> None:
        """`al_ir(indice)`: mover el cursor del historial (app.py valida el rango)."""
        self._al_ir = al_ir
        self._total = 0
        self._aviso = ft.Text(size=13, expand=True)
        self.banner = ft.Container(
            ft.Row(
                [
                    ft.Icon(ft.Icons.HISTORY, color=ft.Colors.ON_TERTIARY_CONTAINER),
                    self._aviso,
                    ft.FilledTonalButton(
                        "Volver al ciclo actual",
                        icon=ft.Icons.LAST_PAGE,
                        on_click=lambda _: al_ir(self._total - 1),
                    ),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            bgcolor=ft.Colors.TERTIARY_CONTAINER,
            border_radius=10,
            padding=10,
        )
        self.exportar = ft.OutlinedButton(
            "Exportar sesión (.json)",
            icon=ft.Icons.SAVE_ALT,
            on_click=al_exportar,
            tooltip="Guardar la sesión (snapshots y programa) en JSON",
        )
        self.reabrir = ft.OutlinedButton(
            "Abrir sesión",
            icon=ft.Icons.FOLDER_OPEN,
            on_click=al_reabrir,
            tooltip="Abrir una sesión exportada, sin placa (hay que estar desconectado)",
        )
        self._marcas = ft.Row(spacing=0, height=14)
        # on_change_end y no on_change: arrastrando, on_change llega decenas de veces y cada
        # una refresca todas las vistas.
        self.deslizador = ft.Slider(
            min=0,
            max=1,
            value=0,
            on_change_end=lambda e: al_ir(round(e.control.value)),
        )
        self._texto = ft.Text(size=12, color=ft.Colors.ON_SURFACE_VARIANT)
        leyenda = ft.Row([chip(n, k) for k, n in NOMBRE_RIESGO.items()], spacing=6)
        encabezado = ft.Container(
            ft.Row(
                [
                    *(
                        ft.Text(t, size=12, weight=ft.FontWeight.W_600, width=w)
                        for t, w in zip(
                            ("Ciclo", "PC", "IF │ ID │ EX │ MEM │ WB", "Riesgos"),
                            _ANCHOS,
                            strict=True,
                        )
                    ),
                    ft.Text("Cambios", size=12, weight=ft.FontWeight.W_600),
                ],
            ),
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            padding=ft.Padding.symmetric(horizontal=8, vertical=4),
        )
        self._tabla = ft.ListView(spacing=0, expand=True)
        self.control = ft.Column(
            [
                self.banner,
                ft.Row(
                    [
                        titulo("Historial"),
                        self._texto,
                        ft.Container(expand=True),
                        self.reabrir,
                        self.exportar,
                    ]
                ),
                tarjeta(self._marcas, self.deslizador, leyenda),
                encabezado,
                self._tabla,
            ],
            expand=True,
            spacing=8,
        )

    def mostrar(
        self,
        indice: int,
        filas: list[FilaHistorial],
        origen: str | None,
        ocupado: bool,
        reabrir: bool,
    ) -> None:
        """`indice` -1: sin historial. `origen`: el archivo de una sesión reabierta.
        `reabrir`: se puede abrir una sesión (hay que estar desconectado)."""
        total = self._total = len(filas)
        navegable = total > 1 and not ocupado  # mientras opera, la sesión mueve el cursor
        self.deslizador.disabled = not navegable
        self.deslizador.max = max(total - 1, 1)  # min == max rompe el slider
        self.deslizador.divisions = max(total - 1, 1)
        self.deslizador.value = max(indice, 0)
        self.exportar.disabled = total == 0 or ocupado
        self.reabrir.disabled = not reabrir
        self.banner.visible = 0 <= indice < total - 1
        if self.banner.visible:
            self._aviso.value = (
                f"Estás viendo el ciclo {filas[indice].ciclo} de {filas[-1].ciclo}. Es una copia: "
                "la placa no retrocede, y el próximo Paso sigue desde el último."
            )
        texto = f"{total} snapshots" if total else "Sin snapshots"
        if origen is not None:
            texto += f" · {origen}, sin placa"
        self._texto.value = texto
        desde = max(0, total - MAX_FILAS)
        visibles = filas[desde:]
        # Una marca por ciclo: el color del primer evento (o nada).
        self._marcas.controls = [
            ft.Container(
                expand=1,
                height=14 if i + desde == indice else 8,
                bgcolor=(
                    ft.Colors.PRIMARY
                    if i + desde == indice
                    else RIESGO[f.eventos[0]][0]
                    if f.eventos
                    else ft.Colors.OUTLINE_VARIANT
                ),
                margin=ft.Margin.symmetric(horizontal=0.5),
                tooltip=f"Ciclo {f.ciclo}",
            )
            for i, f in enumerate(visibles)
        ]
        self._tabla.controls = [
            ft.Container(
                ft.Row(
                    [
                        _t(str(f.ciclo), _ANCHOS[0]),
                        _t(f"0x{f.pc:03x}", _ANCHOS[1]),
                        _t(" │ ".join(e.ljust(4) for e in f.etapas), _ANCHOS[2]),
                        ft.Row(
                            [chip(NOMBRE_RIESGO[e], e) for e in f.eventos],
                            spacing=3,
                            width=_ANCHOS[3],
                        ),
                        _t(f.cambios, tenue=True),
                    ],
                ),
                padding=ft.Padding.symmetric(horizontal=8, vertical=2),
                bgcolor=ft.Colors.PRIMARY_CONTAINER if i + desde == indice else None,
                on_click=None if ocupado else (lambda _, i=i: self._al_ir(i + desde)),
            )
            for i, f in enumerate(visibles)
        ]
