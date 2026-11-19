"""Vista del pipeline (US-502): las 5 etapas con su instrucción y las marcas del ciclo.

Qué va en cada columna y qué significa cada marca lo decide `ui/pipeline.py`; acá solo se
pinta. Los controles se crean una vez y después se les cambian las propiedades: rearmarlos en
cada paso los haría reconciliar contra los viejos (ver `editor_view.mostrar_listado`).
"""

from collections.abc import Callable

import flet as ft

from riscv_toolkit.ui.pipeline import ETAPAS, LATCH_DE_COLUMNA, Columna
from riscv_toolkit.ui.tema import FUENTE_CODIGO

# Marcas de riesgo con relleno (base visual de la maqueta). Rol de color → qué marca.
_COLOR_STALL = ft.Colors.TERTIARY_CONTAINER
_COLOR_FLUSH = ft.Colors.ERROR_CONTAINER
_COLOR_FWD = ft.Colors.PRIMARY_CONTAINER
_ANCHO_MIN = 150


def _chip(texto: str, color: str) -> ft.Container:
    return ft.Container(
        ft.Text(texto, size=11, weight=ft.FontWeight.W_600, font_family=FUENTE_CODIGO),
        bgcolor=color,
        border_radius=4,
        padding=ft.Padding.symmetric(horizontal=6, vertical=1),
    )


class _Tarjeta:
    """Una etapa: nombre, PC, instrucción y marcas."""

    def __init__(self, etapa: str, al_tocar: Callable[[str], None]) -> None:
        self.etapa = etapa
        self.pc = ft.Text(size=12, font_family=FUENTE_CODIGO, color=ft.Colors.ON_SURFACE_VARIANT)
        self.texto = ft.Text(size=14, font_family=FUENTE_CODIGO, no_wrap=True)
        self.marcas = ft.Row(spacing=4, wrap=True)
        latch = LATCH_DE_COLUMNA.get(etapa)
        self.control = ft.Container(
            ft.Column(
                [
                    ft.Row(
                        [
                            ft.Text(etapa, weight=ft.FontWeight.W_600, size=16),
                            ft.Text(latch or "PC", size=11, color=ft.Colors.ON_SURFACE_VARIANT),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    self.pc,
                    self.texto,
                    self.marcas,
                ],
                spacing=4,
            ),
            expand=True,
            padding=10,
            border_radius=8,
            border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
            # IF no tiene latch propio: tocarla no elige nada.
            on_click=(lambda _: al_tocar(latch)) if latch else None,
            tooltip=f"Ver el latch {latch}" if latch else "IF: la instrucción del PC",
        )
        self.mostrar(Columna(etapa))

    def mostrar(self, c: Columna) -> None:
        if c.burbuja:
            self.pc.value = ""
            self.texto.value = "burbuja"
            self.texto.italic = True
            self.texto.color = ft.Colors.ON_SURFACE_VARIANT
            fondo = ft.Colors.SURFACE_CONTAINER_LOW
        else:
            self.pc.value = f"0x{c.pc:08x}" if c.pc is not None else ""
            self.texto.value = c.texto
            self.texto.italic = False
            self.texto.color = ft.Colors.ERROR if c.ilegal else None
            fondo = (
                ft.Colors.ERROR_CONTAINER
                if c.ilegal
                else ft.Colors.SECONDARY_CONTAINER
                if c.halt
                else ft.Colors.SURFACE_CONTAINER_HIGH
            )
        # Anulada (flush): tachada. Va en el estilo para no pisar el resto del texto.
        self.texto.style = ft.TextStyle(
            decoration=ft.TextDecoration.LINE_THROUGH if c.anulada else ft.TextDecoration.NONE
        )
        self.control.bgcolor = fondo
        chips: list[ft.Control] = []
        if c.congelada:
            chips.append(_chip("STALL", _COLOR_STALL))
        if c.anulada:
            chips.append(_chip("FLUSH", _COLOR_FLUSH))
        if c.ilegal:
            chips.append(_chip("ILEGAL", _COLOR_FLUSH))
        chips += [_chip(m, _COLOR_FWD) for m in c.marcas]
        self.marcas.controls = chips


class VistaPipeline:
    """Las 5 tarjetas en fila y una leyenda de las marcas."""

    def __init__(self, al_elegir_latch: Callable[[str], None]) -> None:
        self._tarjetas = [_Tarjeta(e, al_elegir_latch) for e in ETAPAS]
        leyenda = ft.Row(
            [
                _chip("STALL", _COLOR_STALL),
                ft.Text("IF e ID se congelan; entra una burbuja a EX", size=12),
                _chip("FLUSH", _COLOR_FLUSH),
                ft.Text("se descarta", size=12),
                _chip("A ← EX/MEM", _COLOR_FWD),
                ft.Text("forwarding hacia EX (y la etapa fuente)", size=12),
            ],
            wrap=True,
            spacing=8,
        )
        self.control = ft.Column(
            [ft.Row([t.control for t in self._tarjetas], spacing=8), leyenda], spacing=10
        )

    def mostrar(self, columnas: list[Columna] | None, latch_elegido: str) -> None:
        """None: no hay snapshot (desconectado). La etapa del latch elegido va con borde."""
        for i, tarjeta in enumerate(self._tarjetas):
            tarjeta.mostrar(columnas[i] if columnas is not None else Columna(tarjeta.etapa))
            elegida = LATCH_DE_COLUMNA.get(tarjeta.etapa) == latch_elegido
            tarjeta.control.border = ft.Border.all(
                2 if elegida else 1,
                ft.Colors.PRIMARY if elegida else ft.Colors.OUTLINE_VARIANT,
            )
