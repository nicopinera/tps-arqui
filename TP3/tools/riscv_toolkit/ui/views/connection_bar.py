"""Barra de conexión (US-501): puerto, Conectar/Desconectar, indicador y versión."""

from collections.abc import Awaitable, Callable

import flet as ft

SIMULADO = "Simulado (sin placa)"  # opción del desplegable que usa FakeTransport


class BarraConexion:
    """Arma los controles; `app.py` decide qué hacer con el clic y le pasa el resultado."""

    def __init__(
        self,
        al_conectar: Callable[[], Awaitable[None]],
        al_refrescar: Callable[[], None],
    ) -> None:
        self.puerto = ft.Dropdown(label="Puerto", width=260, dense=True)
        self.refrescar = ft.IconButton(
            ft.Icons.REFRESH, tooltip="Volver a buscar puertos", on_click=lambda _: al_refrescar()
        )
        self.boton = ft.FilledButton("Conectar", icon=ft.Icons.LINK, on_click=al_conectar)
        self._luz = ft.Icon(ft.Icons.CIRCLE, size=12)
        self._texto = ft.Text()
        self.control = ft.Row(
            [self.puerto, self.refrescar, self.boton, self._luz, self._texto],
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        )
        self.mostrar(conectado=False, simulado=False, version=None, puerto=None)

    def poner_puertos(self, puertos: list[str], elegido: str) -> None:
        """Llena el desplegable: los puertos reales más la opción simulada."""
        self.puerto.options = [ft.DropdownOption(p) for p in [*puertos, SIMULADO]]
        self.puerto.value = elegido

    def mostrar(
        self, conectado: bool, simulado: bool, version: int | None, puerto: str | None
    ) -> None:
        """Indicador desconectado / conectado / simulado, y la versión de `PING`."""
        if not conectado:
            self._luz.color = ft.Colors.OUTLINE
            self._texto.value = "Desconectado"
        elif simulado:
            self._luz.color = ft.Colors.TERTIARY
            self._texto.value = f"Simulado · protocolo v{version}"
        else:
            self._luz.color = ft.Colors.PRIMARY
            self._texto.value = f"Conectado a {puerto} · protocolo v{version}"
        self.boton.content = "Desconectar" if conectado else "Conectar"
        self.boton.icon = ft.Icons.LINK_OFF if conectado else ft.Icons.LINK
        self.puerto.disabled = conectado
        self.refrescar.disabled = conectado
