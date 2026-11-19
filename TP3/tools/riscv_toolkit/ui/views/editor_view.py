"""Panel de programa (US-501): editor, mensajes del ensamblador y listado con la línea en
ejecución resaltada.

Flet no trae un editor de código: el editor es un `TextField` multilínea, que no puede
numerar ni resaltar líneas. Por eso la línea en ejecución se resalta en el listado (ADR-012,
D2) y debajo del editor se muestra la posición del cursor (`Ln N`).
"""

from collections.abc import Awaitable, Callable

import flet as ft

from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.ui.state import Etapa, linea_de, rango_de_linea
from riscv_toolkit.ui.tema import FUENTE_CODIGO


class PanelPrograma:
    """Editor | listado, con los mensajes del ensamblador abajo."""

    def __init__(
        self,
        al_abrir: Callable[[], Awaitable[None]],
        al_guardar: Callable[[], Awaitable[None]],
        al_ensamblar: Callable[[], None],
        al_editar: Callable[[], None],
        al_cambiar_etapa: Callable[[], None],
    ) -> None:
        self.editor = ft.TextField(
            multiline=True,
            border=ft.InputBorder.NONE,  # el borde lo pone el contenedor (ver `caja`)
            text_style=ft.TextStyle(font_family=FUENTE_CODIGO, size=13),
            hint_text="Escribí un programa o abrí un .asm (Ctrl+O)",
            on_change=lambda _: al_editar(),
            on_selection_change=self._cursor_movido,
        )
        self._cursor = ft.Text("Ln 1", size=12, color=ft.Colors.ON_SURFACE_VARIANT)
        self._archivo = ft.Text("sin archivo", size=12, color=ft.Colors.ON_SURFACE_VARIANT)
        self.mensajes = ft.Column(spacing=2)
        self.listado = ft.ListView(expand=True, spacing=0)
        self._filas: list[ft.Container] = []  # las del listado, por dirección / 4
        self._generacion = 0  # cambia con cada listado: va en la clave de cada fila
        self.etapa = ft.SegmentedButton(
            segments=[ft.Segment(e.name, label=f"Seguir {e.name}") for e in Etapa],
            selected=[Etapa.IF.name],
            on_change=lambda _: al_cambiar_etapa(),
        )
        botones = ft.Row(
            [
                ft.TextButton(
                    "Abrir", icon=ft.Icons.FOLDER_OPEN, tooltip="Ctrl+O", on_click=al_abrir
                ),
                ft.TextButton("Guardar", icon=ft.Icons.SAVE, tooltip="Ctrl+S", on_click=al_guardar),
                ft.FilledTonalButton(
                    "Ensamblar",
                    icon=ft.Icons.BUILD,
                    tooltip="Ctrl+B",
                    on_click=lambda _: al_ensamblar(),
                ),
                self._archivo,
            ]
        )
        # El TextField de Flet no puede estirarse al alto disponible (no expone `expands` de
        # Flutter): el que se estira y scrollea es este contenedor con borde.
        caja = ft.Container(
            ft.Column(
                [self.editor],
                scroll=ft.ScrollMode.AUTO,
                horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
            ),
            expand=True,
            padding=ft.Padding.symmetric(horizontal=12),
            border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
            border_radius=8,
        )
        izquierda = ft.Column(
            [botones, caja, ft.Row([self._cursor]), self.mensajes],
            expand=True,
            horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
        )
        derecha = ft.Column(
            [
                ft.Row([ft.Text("Listado", weight=ft.FontWeight.W_600), self.etapa]),
                ft.Container(
                    self.listado,
                    expand=True,
                    border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
                    border_radius=8,
                ),
            ],
            expand=True,
        )
        self.control = ft.Row([izquierda, derecha], expand=True, spacing=16)

    # --- Editor ----------------------------------------------------------------------------

    def _cursor_movido(self, e: ft.TextSelectionChangeEvent[ft.TextField]) -> None:
        self._cursor.value = f"Ln {linea_de(self.editor.value or '', e.selection.base_offset)}"

    def poner_archivo(self, nombre: str | None) -> None:
        self._archivo.value = nombre if nombre is not None else "sin archivo"

    async def ir_a_linea(self, linea: int) -> None:
        """Selecciona la línea `linea` del editor (clic en un error, AC2)."""
        await self.editor.focus()  # sin foco, Flutter no muestra la selección
        inicio, fin = rango_de_linea(self.editor.value or "", linea)
        self.editor.selection = ft.TextSelection(base_offset=inicio, extent_offset=fin)
        self.editor.update()

    # --- Mensajes del ensamblador ----------------------------------------------------------

    def mostrar_mensajes(
        self,
        error: tuple[int, str] | None,
        advertencias: list[str],
        al_tocar_error: Callable[[int], Awaitable[None]],
    ) -> None:
        """El error (clickeable: lleva a la línea) y las advertencias, que no traen línea."""
        filas: list[ft.Control] = []
        if error is not None:
            linea, texto = error

            async def ir(_: ft.Event[ft.ListTile]) -> None:
                await al_tocar_error(linea)

            filas.append(
                ft.ListTile(
                    leading=ft.Icon(ft.Icons.ERROR, color=ft.Colors.ERROR),
                    title=ft.Text(f"Línea {linea}: {texto}", color=ft.Colors.ERROR),
                    dense=True,
                    on_click=ir,
                )
            )
        filas += [
            ft.ListTile(
                leading=ft.Icon(ft.Icons.WARNING_AMBER, color=ft.Colors.TERTIARY),
                title=ft.Text(a),
                dense=True,
            )
            for a in advertencias
        ]
        self.mensajes.controls = filas

    # --- Listado ---------------------------------------------------------------------------

    def etapa_elegida(self) -> Etapa:
        return Etapa[self.etapa.selected[0]] if self.etapa.selected else Etapa.IF

    def mostrar_listado(self, imagen: Imagen | None, texto: str) -> None:
        """Una fila por instrucción: dirección, palabra, línea y fuente (como el `.lst`)."""
        # Flet 1.0 reconcilia las listas por clave (como React): si el listado nuevo reusara
        # las claves del viejo (0, 4, 8…), sus filas quedarían emparejadas con las viejas y
        # "congeladas", y pintarlas después tira "Frozen controls cannot be updated".
        self._generacion += 1
        fuente = texto.split("\n")
        palabras = imagen.palabras if imagen is not None else []
        mapa = imagen.mapa_lineas if imagen is not None else {}
        filas: list[ft.Container] = []
        for i, palabra in enumerate(palabras):
            direccion = 4 * i
            nro = mapa.get(direccion)
            codigo = fuente[nro - 1].strip() if nro is not None else "halt  (agregado)"
            filas.append(
                ft.Container(
                    ft.Text(
                        f"{direccion:04x}  {palabra:08x}  {nro or '':>4}  {codigo}",
                        font_family=FUENTE_CODIGO,
                        size=13,
                        no_wrap=True,
                    ),
                    # El decorador de Flet le oculta el constructor a mypy.
                    key=ft.ScrollKey(self._clave(direccion)),  # type: ignore[call-arg]
                    padding=ft.Padding.symmetric(horizontal=8, vertical=1),
                )
            )
        self._filas = filas
        self.listado.controls = list(filas)

    def resaltar(self, pc: int | None) -> bool:
        """Pinta la fila de `pc` y despinta las demás. False si `pc` no está en el listado."""
        for i, fila in enumerate(self._filas):
            fila.bgcolor = ft.Colors.PRIMARY_CONTAINER if 4 * i == pc else None
        return pc is not None and 0 <= pc < 4 * len(self._filas)

    async def mostrar_fila(self, pc: int) -> None:
        """Lleva el scroll del listado hasta la fila de `pc`."""
        await self.listado.scroll_to(scroll_key=self._clave(pc), duration=150)

    def _clave(self, direccion: int) -> str:
        return f"{self._generacion}:{direccion}"
