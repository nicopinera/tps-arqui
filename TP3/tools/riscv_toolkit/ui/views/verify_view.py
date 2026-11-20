"""Página Verificar (US-505, AC3): el estado final contra el golden model.

Coincide: banner verde y la tabla de lo comparado. No coincide: banner rojo, la tabla (con
"Solo diferencias") y "Por dónde empezar": quién escribió cada valor distinto, con un botón
que lleva a ese ciclo.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass

import flet as ft

from riscv_toolkit.session.verificar import Diferencia
from riscv_toolkit.ui.tema import FUENTE_CODIGO, RIESGO, chip, tarjeta, titulo


@dataclass(frozen=True)
class Verificacion:
    """Lo que muestra la página después de Verificar."""

    filas: list[Diferencia]  # `comparacion`: todo lo comparado
    ciclos: int  # los de la placa
    esperado: str  # "HALTED en 0x02c" (golden model)
    origenes: dict[str, tuple[int, str, int]]  # qué → (índice, instrucción, ciclo)


def _t(valor: str, color: str | None = None, negrita: bool = False) -> ft.Text:
    return ft.Text(
        valor,
        font_family=FUENTE_CODIGO,
        size=13,
        color=color,
        weight=ft.FontWeight.W_600 if negrita else None,
    )


def _decimal(hexa: str) -> str:
    """ "0xfffffffd" → "-3"; lo que no es un número ("no escrita", "HALTED"), vacío."""
    if not hexa.startswith("0x"):
        return ""
    v = int(hexa, 16)
    return str(v - (1 << 32) if v >> 31 else v)


class VistaVerificar:
    def __init__(
        self, al_verificar: Callable[[], Awaitable[None]], al_ir: Callable[[int], None]
    ) -> None:
        self._al_ir = al_ir
        self.boton = ft.FilledButton(
            "Verificar",
            icon=ft.Icons.FACT_CHECK,
            on_click=al_verificar,
            tooltip="Corre el programa en el golden model y compara el estado final",
        )
        self._mensaje = ft.Text(size=13, expand=True)
        self._icono = ft.Icon(ft.Icons.INFO_OUTLINE)
        self.banner = ft.Container(
            ft.Row([self._icono, self._mensaje]), border_radius=10, padding=12
        )
        self.filtro = ft.SegmentedButton(
            segments=[ft.Segment(n, label=n) for n in ("Todo", "Solo diferencias")],
            selected=["Todo"],
            on_change=lambda _: self.mostrar(self._ultimo),
        )
        self._ocultos = ft.Row()
        self._tabla = ft.DataTable(
            columns=[
                ft.DataColumn(label=t) for t in ("Dónde", "Esperado", "Dec", "Obtenido", "Dec", "")
            ],
            heading_row_color=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            data_row_min_height=26,
            data_row_max_height=26,
            heading_row_height=30,
            column_spacing=22,
        )
        self._como = ft.Column(spacing=4)
        self._empezar = ft.Column(spacing=6)
        self.tarjeta_empezar = tarjeta(titulo("Por dónde empezar"), self._empezar)
        self._detalle = ft.Row(
            [
                ft.Column([ft.Row([self.filtro, self._ocultos]), self._tabla], expand=3),
                ft.Column(
                    [tarjeta(titulo("Cómo se verificó"), self._como), self.tarjeta_empezar],
                    expand=2,
                ),
            ],
            vertical_alignment=ft.CrossAxisAlignment.START,
        )
        self.control = ft.Column(
            [
                ft.Row(
                    [
                        titulo("Verificar contra el golden model"),
                        self.boton,
                        ft.Text(
                            "Compara el último snapshot: motivo, registros y memoria usada "
                            "(el PC no).",
                            size=12,
                            color=ft.Colors.ON_SURFACE_VARIANT,
                        ),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                self.banner,
                self._detalle,
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=12,
        )
        self._ultimo: Verificacion | str | None = None
        self.mostrar(None)

    def _banner(self, texto: str, clave: str | None, icono: ft.IconData) -> None:
        color, fondo = RIESGO[clave] if clave else (None, ft.Colors.SURFACE_CONTAINER_HIGH)
        self._mensaje.value, self._mensaje.color = texto, color
        self._icono.icon, self._icono.color = icono, color
        self.banner.bgcolor = fondo

    def mostrar(self, resultado: Verificacion | str | None) -> None:
        """Texto: por qué no se pudo verificar. None: todavía no se verificó."""
        self._ultimo = resultado
        self._detalle.visible = isinstance(resultado, Verificacion)
        if resultado is None:
            self._banner(
                "Corré el programa hasta el final y tocá Verificar.", None, ft.Icons.INFO_OUTLINE
            )
            return
        if isinstance(resultado, str):
            self._banner(resultado, None, ft.Icons.INFO_OUTLINE)
            return
        malas = [d for d in resultado.filas if not d.ok]
        regs = sum(d.que.startswith("x") for d in resultado.filas)
        palabras = sum(d.que.startswith("[") for d in resultado.filas)
        if not malas:
            self._banner(
                f"Coincide. Los 32 registros, las {palabras} palabras de memoria usada y el "
                "motivo son iguales a los del golden model.",
                "ok",
                ft.Icons.CHECK_CIRCLE,
            )
        else:
            n = len(malas)
            self._banner(
                f"{n} diferencia{'s' if n != 1 else ''} con el golden model. Abajo, por dónde "
                "empezar a buscar.",
                "fl",
                ft.Icons.CANCEL,
            )
        solo_malas = (self.filtro.selected or ["Todo"])[0] == "Solo diferencias"
        self._tabla.rows = [
            ft.DataRow(
                [
                    ft.DataCell(_t(d.que, negrita=True)),
                    ft.DataCell(_t(d.esperado)),
                    ft.DataCell(_t(_decimal(d.esperado), ft.Colors.ON_SURFACE_VARIANT)),
                    ft.DataCell(_t(d.obtenido)),
                    ft.DataCell(_t(_decimal(d.obtenido), ft.Colors.ON_SURFACE_VARIANT)),
                    ft.DataCell(
                        _t("✓" if d.ok else "✗", RIESGO["ok" if d.ok else "fl"][0], negrita=True)
                    ),
                ],
                color=None if d.ok else ft.Colors.ERROR_CONTAINER,
            )
            for d in resultado.filas
            if not (solo_malas and d.ok)
        ]
        self._ocultos.controls = [chip(f"Ocultos: {32 - regs} registros en 0, iguales")]
        self._como.controls = [
            ft.Text(f"Placa: el último snapshot, ciclo {resultado.ciclos}.", size=13),
            ft.Text(
                f"Golden model: el mismo programa en el ISS de Python, {resultado.esperado}.",
                size=13,
            ),
            ft.Text(
                "El PC no se compara: en la placa queda unos ciclos después del HALT.",
                size=12,
                color=ft.Colors.ON_SURFACE_VARIANT,
            ),
        ]
        self.tarjeta_empezar.visible = bool(malas)
        filas: list[ft.Control] = []
        for d in malas:
            origen = resultado.origenes.get(d.que)
            if origen is None:
                filas.append(
                    ft.Text(
                        f"{d.que}: no se sabe quién lo escribió (cambió en un RUN, "
                        "o no cambió nunca).",
                        size=12,
                    )
                )
                continue
            indice, texto, ciclo = origen
            filas.append(
                ft.Row(
                    [
                        ft.Column(
                            [
                                _t(f"{d.que} = {d.obtenido}", negrita=True),
                                ft.Text(f"lo escribió {texto} en el ciclo {ciclo}", size=12),
                            ],
                            spacing=0,
                            expand=True,
                        ),
                        ft.OutlinedButton(
                            f"Ir al ciclo {ciclo}", on_click=lambda _, i=indice: self._al_ir(i)
                        ),
                    ],
                )
            )
        self._empezar.controls = filas
