"""Página Programa (US-501): editor o fuente en ejecución | listado, y la tarjeta Problemas.

Dos modos:
- **Edición:** el editor (un `TextField` multilínea: Flet no trae un editor de código, así que
  no puede numerar ni marcar líneas; los errores van en la tarjeta Problemas con "Ir").
- **Ejecución** (hay un programa cargado y se está ejecutando): la fuente de solo lectura,
  numerada, con la línea en ejecución marcada y la etapa en la que está cada línea.

El listado es el mismo en los dos modos, también con las etapas.
"""

from collections.abc import Awaitable, Callable
from typing import cast

import flet as ft

from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.ui.state import Etapa, linea_de, rango_de_linea
from riscv_toolkit.ui.tema import FUENTE_CODIGO, RIESGO, tarjeta, titulo

_ALTO_FILA = 22


def _codigo(valor: str = "", color: str | None = None) -> ft.Text:
    return ft.Text(valor, font_family=FUENTE_CODIGO, size=13, no_wrap=True, color=color)


def _etiqueta() -> ft.Container:
    """La etapa en la que está una línea ("EX", "IF·MEM" en un loop)."""
    return ft.Container(
        ft.Text(
            "",
            size=10,
            weight=ft.FontWeight.W_600,
            font_family=FUENTE_CODIGO,
            color=ft.Colors.ON_PRIMARY_CONTAINER,
        ),
        bgcolor=ft.Colors.PRIMARY_CONTAINER,
        border_radius=4,
        padding=ft.Padding.symmetric(horizontal=4),
        visible=False,
    )


def _poner_etiqueta(etiqueta: ft.Container, etapas: list[str]) -> None:
    etiqueta.visible = bool(etapas)
    cast(ft.Text, etiqueta.content).value = "·".join(etapas)


def _marcar(fila: ft.Container, actual: bool) -> None:
    """La fila en ejecución: fondo y una barra a la izquierda."""
    fila.bgcolor = ft.Colors.PRIMARY_CONTAINER if actual else None
    fila.border = ft.Border.only(
        left=ft.BorderSide(3, ft.Colors.PRIMARY if actual else ft.Colors.TRANSPARENT)
    )


class PanelPrograma:
    def __init__(
        self,
        al_guardar: Callable[[], Awaitable[None]],
        al_editar: Callable[[], None],
        al_cambiar_etapa: Callable[[], None],
        al_cambiar_modo: Callable[[bool], None],
    ) -> None:
        """`al_cambiar_modo(editar)`: el botón Editar / Ver la ejecución."""
        self.editando = True
        self.editor = ft.TextField(
            multiline=True,
            border=ft.InputBorder.NONE,  # el borde lo pone el contenedor (ver `caja`)
            text_style=ft.TextStyle(font_family=FUENTE_CODIGO, size=13),
            hint_text="Escribí un programa o abrí un .asm (Ctrl+O)",
            on_change=lambda _: al_editar(),
            on_selection_change=self._cursor_movido,
        )
        self._cursor = ft.Text("Ln 1", size=12, color=ft.Colors.ON_SURFACE_VARIANT)
        self.listado = ft.ListView(expand=True, spacing=0)
        self._vacio = ft.Text(
            "Sin listado. Ensamblá el programa (Ctrl+B).",
            size=12,
            italic=True,
            color=ft.Colors.ON_SURFACE_VARIANT,
        )
        self._filas: list[ft.Container] = []  # las del listado, por dirección / 4
        self._etiquetas: list[ft.Container] = []  # la etapa de cada fila del listado
        self._generacion = 0  # cambia con cada listado: va en la clave de cada fila
        self._mapa: dict[int, int] = {}  # dirección → línea (de la imagen del listado)
        self.etapa = ft.SegmentedButton(
            segments=[ft.Segment(e.name, label=e.name) for e in Etapa],
            selected=[Etapa.IF.name],
            on_change=lambda _: al_cambiar_etapa(),
        )
        # --- Encabezado ---
        self._titulo = titulo("Editor")
        self._solo_lectura = ft.Container(
            ft.Text("Solo lectura mientras se ejecuta", size=11),
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
            border_radius=10,
            padding=ft.Padding.symmetric(horizontal=8, vertical=2),
        )
        self.guardar = ft.TextButton(
            "Guardar", icon=ft.Icons.SAVE, tooltip="Ctrl+S", on_click=al_guardar
        )
        self.modo = ft.TextButton(on_click=lambda _: al_cambiar_modo(not self.editando))
        encabezado = ft.Row(
            [
                self._titulo,
                self._solo_lectura,
                self.guardar,
                self._cursor,
                ft.Container(expand=True),
                ft.Text("Resaltar la línea en", size=12),
                self.etapa,
                self.modo,
            ],
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        )
        # --- Izquierda: editor o fuente ---
        # El TextField de Flet no puede estirarse al alto disponible (no expone `expands` de
        # Flutter): el que se estira y scrollea es este contenedor con borde.
        self._caja = ft.Container(
            ft.Column(
                [self.editor],
                scroll=ft.ScrollMode.AUTO,
                horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
            ),
            expand=True,
            padding=ft.Padding.symmetric(horizontal=12),
        )
        self.fuente = ft.ListView(expand=True, spacing=0, visible=False)
        self._lineas: list[ft.Container] = []
        self._etiquetas_fuente: list[ft.Container] = []
        self._pila = ft.Stack([self._caja, self.fuente], expand=True)
        izquierda = ft.Container(
            self._pila,
            expand=True,
            border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
            border_radius=8,
        )
        self._pila_listado = ft.Stack(
            [ft.Container(self._vacio, padding=12), self.listado], expand=True
        )
        derecha = ft.Column(
            [
                ft.Row(
                    [
                        titulo("Listado"),
                        ft.Text(
                            "dirección · palabra · instrucción",
                            size=12,
                            color=ft.Colors.ON_SURFACE_VARIANT,
                        ),
                    ],
                ),
                ft.Container(
                    self._pila_listado,
                    expand=True,
                    border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
                    border_radius=8,
                ),
            ],
            expand=True,
        )
        # --- Problemas ---
        self._resumen_problemas = ft.Text(size=12)
        self.mensajes = ft.Column(spacing=2)
        self.control = ft.Column(
            [
                encabezado,
                ft.Row(
                    [izquierda, derecha],
                    expand=True,
                    spacing=12,
                    vertical_alignment=ft.CrossAxisAlignment.STRETCH,
                ),
                tarjeta(ft.Row([titulo("Problemas"), self._resumen_problemas]), self.mensajes),
            ],
            expand=True,
        )
        self.editando = True
        self.mostrar_modo(editando=True, ciclo=None, se_puede_ver=False)

    # --- Modo --------------------------------------------------------------------------------

    def mostrar_modo(self, editando: bool, ciclo: int | None, se_puede_ver: bool) -> None:
        """`se_puede_ver`: hay una ejecución del programa del listado para mirar."""
        self.editando = editando
        self._caja.visible = editando
        self.fuente.visible = not editando
        self._solo_lectura.visible = not editando
        self.guardar.visible = self._cursor.visible = editando
        self._titulo.value = "Editor" if editando else f"Ejecutando · ciclo {ciclo}"
        self.modo.visible = se_puede_ver or not editando
        self.modo.content = "Ver la ejecución" if editando else "Editar"
        self.modo.icon = ft.Icons.VISIBILITY if editando else ft.Icons.EDIT

    # --- Editor ----------------------------------------------------------------------------

    def _cursor_movido(self, e: ft.TextSelectionChangeEvent[ft.TextField]) -> None:
        self._cursor.value = f"Ln {linea_de(self.editor.value or '', e.selection.base_offset)}"

    async def ir_a_linea(self, linea: int) -> None:
        """Selecciona la línea `linea` del editor (clic en un error, AC2)."""
        await self.editor.focus()  # sin foco, Flutter no muestra la selección
        inicio, fin = rango_de_linea(self.editor.value or "", linea)
        self.editor.selection = ft.TextSelection(base_offset=inicio, extent_offset=fin)
        self.editor.update()

    # --- Problemas -------------------------------------------------------------------------

    def mostrar_mensajes(
        self,
        error: tuple[int, str] | None,
        advertencias: list[str],
        al_tocar_error: Callable[[int], Awaitable[None]],
    ) -> None:
        """El error (con "Ir": lleva a la línea) y las advertencias, que no traen línea.

        El ensamblador corta en el primer error: hay a lo sumo uno.
        """
        filas: list[ft.Control] = []
        if error is not None:
            linea, texto = error

            async def ir(_: ft.Event[ft.TextButton]) -> None:
                await al_tocar_error(linea)

            filas.append(
                ft.Row(
                    [
                        ft.Icon(ft.Icons.ERROR, color=RIESGO["fl"][0], size=18),
                        ft.Text(f"Línea {linea}", weight=ft.FontWeight.W_600, size=13),
                        ft.Text(texto, size=13, expand=True),
                        ft.TextButton("Ir", on_click=ir),
                    ]
                )
            )
            self._vacio.value = "Sin listado. Corregí el error y ensamblá de nuevo (Ctrl+B)."
        filas += [
            ft.Row(
                [
                    ft.Icon(ft.Icons.WARNING_AMBER, color=RIESGO["st"][0], size=18),
                    ft.Text(a, size=13, expand=True),
                ],
            )
            for a in advertencias
        ]
        self.mensajes.controls = filas
        n = len(advertencias)
        errores = "1 error" if error is not None else "Sin errores"
        self._resumen_problemas.value = f"{errores} · {n} advertencia{'s' if n != 1 else ''}"
        self._resumen_problemas.color = RIESGO["fl"][0] if error is not None else None
        if error is not None:
            self.mostrar_listado(None, "")

    # --- Listado y fuente ------------------------------------------------------------------

    def etapa_elegida(self) -> Etapa:
        return Etapa[self.etapa.selected[0]] if self.etapa.selected else Etapa.IF

    def mostrar_listado(self, imagen: Imagen | None, texto: str) -> None:
        """Una fila por instrucción (como el `.lst`), y la fuente numerada para ejecutar."""
        # Flet 1.0 reconcilia las listas por clave (como React): si el listado nuevo reusara
        # las claves del viejo (0, 4, 8…), sus filas quedarían emparejadas con las viejas y
        # "congeladas", y pintarlas después tira "Frozen controls cannot be updated".
        self._generacion += 1
        fuente = texto.split("\n")
        palabras = imagen.palabras if imagen is not None else []
        self._mapa = imagen.mapa_lineas if imagen is not None else {}
        filas: list[ft.Container] = []
        self._etiquetas = []
        for i, palabra in enumerate(palabras):
            direccion = 4 * i
            nro = self._mapa.get(direccion)
            codigo = fuente[nro - 1].strip() if nro is not None else "halt  (agregado)"
            etiqueta = _etiqueta()
            self._etiquetas.append(etiqueta)
            filas.append(
                ft.Container(
                    ft.Row(
                        [_codigo(f"{direccion:04x}  {palabra:08x}  {codigo}"), etiqueta],
                        spacing=8,
                    ),
                    # El decorador de Flet le oculta el constructor a mypy.
                    key=ft.ScrollKey(self._clave(direccion)),  # type: ignore[call-arg]
                    padding=ft.Padding.symmetric(horizontal=8),
                    height=_ALTO_FILA,
                )
            )
        self._filas = filas
        self.listado = ft.ListView(list(filas), expand=True, spacing=0)
        self._pila_listado.controls[1] = self.listado
        self._vacio.visible = not filas
        # La fuente de solo lectura, numerada.
        self._lineas, self._etiquetas_fuente = [], []
        if imagen is not None:
            for nro, linea in enumerate(fuente, start=1):
                etiqueta = _etiqueta()
                self._etiquetas_fuente.append(etiqueta)
                self._lineas.append(
                    ft.Container(
                        ft.Row(
                            [
                                _codigo(f"{nro:>3}", color=ft.Colors.ON_SURFACE_VARIANT),
                                ft.Container(etiqueta, width=54),
                                _codigo(linea),
                            ],
                            spacing=8,
                        ),
                        key=ft.ScrollKey(self._clave(-nro)),  # type: ignore[call-arg]
                        padding=ft.Padding.symmetric(horizontal=8),
                        height=_ALTO_FILA,
                    )
                )
        # Una ListView nueva por programa (también la del listado): si a una ListView que ya
        # está en pantalla se le cambian los hijos con clave, la ventana no aplica el cambio y
        # descarta el resto de esa actualización (la barra de estado queda vieja).
        self.fuente = ft.ListView(
            list(self._lineas), expand=True, spacing=0, visible=self.fuente.visible
        )
        self._pila.controls[1] = self.fuente

    def resaltar(self, pc: int | None, etapas: dict[int, list[str]]) -> bool:
        """Marca la fila de `pc` (listado y fuente) y pone la etapa de cada instrucción.

        `etapas`: PC → las etapas en las que está ("IF", "EX"…). False si `pc` no está.
        """
        linea_pc = self._mapa.get(pc) if pc is not None else None
        for i, fila in enumerate(self._filas):
            _marcar(fila, 4 * i == pc)
            _poner_etiqueta(self._etiquetas[i], etapas.get(4 * i, []))
        por_linea: dict[int, list[str]] = {}
        for direccion, es in etapas.items():
            if (nro := self._mapa.get(direccion)) is not None:
                por_linea.setdefault(nro, []).extend(es)
        for nro, (fila, etiqueta) in enumerate(
            zip(self._lineas, self._etiquetas_fuente, strict=True), start=1
        ):
            _marcar(fila, nro == linea_pc)
            _poner_etiqueta(etiqueta, por_linea.get(nro, []))
        return pc is not None and 0 <= pc < 4 * len(self._filas)

    async def mostrar_fila(self, pc: int) -> None:
        """Lleva el scroll del listado (y de la fuente) hasta la fila de `pc`."""
        await self.listado.scroll_to(scroll_key=self._clave(pc), duration=150)
        nro = self._mapa.get(pc)
        if not self.editando and nro is not None:
            await self.fuente.scroll_to(scroll_key=self._clave(-nro), duration=150)

    def _clave(self, direccion: int) -> str:
        return f"{self._generacion}:{direccion}"
