"""Página Datapath: el diagrama del procesador con el valor de cada cable en el ciclo que se ve.

Capas, de abajo hacia arriba (todas en las coordenadas del diagrama, 1 unidad = 1 px del PNG):
1. el PNG del diagrama (`assets/datapath/`, lo genera `scripts/gen_datapath.py`);
2. un canvas con las redes que elige cada mux (forwarding, PC, ALU, WB);
3. los latches y el PC marcados si se congelan (stall) o se vacían (flush);
4. el valor al lado de cada rótulo: lleno = medido (snapshot), en itálica = calculado.

Todo va dentro de un `InteractiveViewer` (rueda = zoom, arrastrar = mover). El dibujo es
siempre claro, así que esta capa usa colores fijos y no los del tema.
"""

from typing import Any

import flet as ft
import flet.canvas as cv

from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.ui.datapath import cargar_mapa, nombre_de, resaltes, valores_datapath
from riscv_toolkit.ui.pipeline import Columna
from riscv_toolkit.ui.tema import FUENTE_CODIGO, RIESGO, chip, titulo

_ETAPAS = ("IF", "ID", "EX", "MEM", "WB")
_MEDIDO = ("#3B2F00", "#FFE9A8")  # texto, fondo
_CALCULADO = ("#123C73", "#DCE8FA")
_NEUTRO = "#2E7D32"  # la entrada que elige un mux cuando no es un riesgo
_DICE = {
    "st": "stall: el enable está en 0, el ciclo que viene tiene lo mismo",
    "fl": "flush: en el próximo flanco entra una burbuja (valid = 0)",
}


def _ancho_texto(texto: str, letra: int) -> float:
    """Aproximado: la letra del diagrama (Helvetica) mide ~0,6 de su tamaño por carácter; lo
    que sigue al nombre ("1:0", el ancho del bus) va como subíndice, más chico."""
    nombre, _, resto = texto.partition(" ")
    return (len(nombre) * 0.6 + len(resto) * 0.4) * letra


class VistaDatapath:
    def __init__(self) -> None:
        self._mapa: dict[str, Any] = cargar_mapa()
        ancho, alto = self._mapa["ancho"], self._mapa["alto"]
        self._tamaño: tuple[float, float] | None = None
        self._ajustado = False

        self._valores: list[tuple[str, ft.Container, ft.Text]] = []
        self._etapas: dict[str, ft.Text] = {}
        for e in self._mapa["etiquetas"]:
            x, y, w, h = e["rect"]
            letra = e["letra"]
            ancho_texto = _ancho_texto(e["texto"], letra)
            inicio = {"left": x, "right": x + w - ancho_texto}.get(
                e["alinea"], x + (w - ancho_texto) / 2
            )
            if e["texto"] in _ETAPAS and letra >= 14:  # los títulos de columna
                texto = ft.Text("", size=13, font_family=FUENTE_CODIGO, color="#1F3A2E")
                self._etapas[e["texto"]] = texto
                arriba = ft.Container(texto, left=inicio + ancho_texto + 8, top=y - 2)
                self._valores.append(("", arriba, texto))
                continue
            texto = ft.Text("", size=letra, font_family=FUENTE_CODIGO, no_wrap=True)
            caja = ft.Container(
                texto,
                left=inicio + ancho_texto + 3,
                top=y + h / 2 - letra * 0.75,
                padding=ft.Padding.symmetric(horizontal=3),
                border_radius=3,
                visible=False,
            )
            self._valores.append((nombre_de(e["texto"]), caja, texto))

        self._bloques = {
            nombre: ft.Container(
                left=x - 4, top=y - 4, width=w + 8, height=h + 8, border_radius=4, visible=False
            )
            for nombre, (x, y, w, h) in self._mapa["latches"].items()
        }
        # Un Canvas nuevo en cada `mostrar`, no `shapes` cambiado: Flet 1.0.5 no aplica bien el
        # diff de `shapes` después de sacar y volver a poner la página (la ventana se queda en
        # el ciclo viejo, y también lo que viene después en el árbol, como la barra de estado).
        self._redes = ft.Container(width=ancho, height=alto)
        dibujo = ft.Container(
            ft.Stack(
                [
                    ft.Image(src="datapath/datapath.png", width=ancho, height=alto),
                    self._redes,
                    *self._bloques.values(),
                    *(caja for _, caja, _ in self._valores),
                ],
                width=ancho,
                height=alto,
            ),
            bgcolor="#FFFFFF",
            theme_mode=ft.ThemeMode.LIGHT,
        )
        self._visor = ft.InteractiveViewer(
            dibujo,
            constrained=False,
            min_scale=0.2,
            max_scale=4,
            boundary_margin=ft.Margin.all(400),
            expand=True,
            on_size_change=self._al_cambiar_tamaño,
        )
        self._ver_valores = ft.Switch(
            label="Valores", value=True, on_change=lambda _: self._mostrar_valores()
        )
        self.control = ft.Column(
            [
                ft.Row(
                    [
                        titulo("Datapath"),
                        _caja_leyenda("medido", _MEDIDO, False),
                        _caja_leyenda("calculado", _CALCULADO, True),
                        chip("stall", "st"),
                        chip("flush", "fl"),
                        chip("forwarding A", "fa"),
                        chip("forwarding B", "fb"),
                        ft.Container(expand=True),
                        self._ver_valores,
                        ft.IconButton(ft.Icons.ZOOM_OUT, tooltip="Alejar", on_click=self._alejar),
                        ft.IconButton(ft.Icons.ZOOM_IN, tooltip="Acercar", on_click=self._acercar),
                        ft.IconButton(
                            ft.Icons.FIT_SCREEN, tooltip="Ver entero", on_click=self.ajustar
                        ),
                    ],
                    spacing=8,
                ),
                ft.Text(
                    "Medido: viene en el snapshot (los latches). Calculado: lo combinacional, "
                    "recalculado por el modelo del pipeline desde ese estado. Rueda: zoom; "
                    "arrastrar: mover.",
                    size=12,
                    color=ft.Colors.ON_SURFACE_VARIANT,
                ),
                ft.Container(
                    self._visor,
                    expand=True,
                    border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
                    border_radius=8,
                    clip_behavior=ft.ClipBehavior.HARD_EDGE,
                ),
            ],
            expand=True,
            spacing=6,
        )

    # --- Zoom ------------------------------------------------------------------------------

    async def _al_cambiar_tamaño(self, e: ft.LayoutSizeChangeEvent[ft.LayoutControl]) -> None:
        self._tamaño = (e.width, e.height)
        if not self._ajustado:  # la primera vez que se ve: el diagrama entero
            self._ajustado = True
            await self.ajustar()

    async def ajustar(self, _: object = None) -> None:
        """El diagrama entero. También al volver a la página: Flet arma el visor de nuevo y
        arranca en escala 1. La primera vez todavía no se sabe el tamaño: lo hace
        `_al_cambiar_tamaño`."""
        if self._tamaño is None:
            return
        w, h = self._tamaño
        try:
            await self._visor.reset()
            await self._visor.zoom(min(w / self._mapa["ancho"], h / self._mapa["alto"]))
        except RuntimeError:  # la ventana se cerró con el ajuste pendiente (run_task)
            pass

    async def _acercar(self, _: object) -> None:
        await self._visor.zoom(1.25)

    async def _alejar(self, _: object) -> None:
        await self._visor.zoom(0.8)

    # --- Contenido -------------------------------------------------------------------------

    def _mostrar_valores(self) -> None:
        for nombre, caja, texto in self._valores:
            if nombre:
                caja.visible = bool(self._ver_valores.value) and texto.value != ""
        self.control.update()

    def mostrar(
        self, snap: Snapshot | None, imem: list[int] | None, columnas: list[Columna] | None
    ) -> None:
        if snap is None:
            for nombre, caja, texto in self._valores:
                texto.value = ""
                caja.visible = not nombre  # los títulos de etapa quedan (vacíos)
            for bloque in self._bloques.values():
                bloque.visible = False
            self._redes.content = None
            return
        nombres = {nombre for nombre, _, _ in self._valores if nombre}
        valores = valores_datapath(snap, imem, nombres)
        for nombre, caja, texto in self._valores:
            if not nombre:
                continue
            v = valores.get(nombre)
            texto.value = v.texto if v is not None else ""
            caja.visible = v is not None and bool(self._ver_valores.value)
            if v is not None:
                color, fondo = _MEDIDO if v.medido else _CALCULADO
                texto.color, texto.italic, caja.bgcolor = color, not v.medido, fondo
        for c in columnas or []:
            if c.etapa in self._etapas:
                self._etapas[c.etapa].value = "burbuja" if c.burbuja else c.texto

        r = resaltes(valores)
        for nombre, bloque in self._bloques.items():
            clave = r.bloques.get(nombre)
            bloque.visible = clave is not None
            if clave is not None:
                bloque.bgcolor = ft.Colors.with_opacity(0.45, RIESGO[clave][1])
                bloque.border = ft.Border.all(3, RIESGO[clave][0])
                bloque.tooltip = _DICE[clave]
        trazos: list[cv.Shape] = []
        for mux, (opcion, clave) in r.muxes.items():
            red = next(e["red"] for e in self._mapa["muxes"][mux] if e["opcion"] == opcion)
            color = RIESGO[clave][0] if clave else _NEUTRO
            pintura = ft.Paint(
                color=ft.Colors.with_opacity(0.8 if clave else 0.45, color),
                stroke_width=5 if clave else 3,
                style=ft.PaintingStyle.STROKE,
                stroke_cap=ft.StrokeCap.ROUND,
                stroke_join=ft.StrokeJoin.ROUND,
            )
            for cable in self._mapa["redes"][red]:
                (x0, y0), *resto = cable
                trazos.append(
                    cv.Path(
                        [cv.Path.MoveTo(x0, y0), *(cv.Path.LineTo(x, y) for x, y in resto)],
                        paint=pintura,
                    )
                )
        ancho, alto = self._mapa["ancho"], self._mapa["alto"]
        self._redes.content = cv.Canvas(trazos, width=ancho, height=alto)


def _caja_leyenda(texto: str, colores: tuple[str, str], italica: bool) -> ft.Container:
    return ft.Container(
        ft.Text(texto, size=11, font_family=FUENTE_CODIGO, color=colores[0], italic=italica),
        bgcolor=colores[1],
        border_radius=4,
        padding=ft.Padding.symmetric(horizontal=6, vertical=1),
    )
