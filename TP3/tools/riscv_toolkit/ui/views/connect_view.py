"""Pantalla de conexión (la primera, y la que se ve desconectado): puerto, aviso del último
fallo, Conectar o Usar sin placa, y los programas del TP para abrir."""

from collections.abc import Awaitable, Callable
from pathlib import Path

import flet as ft

from riscv_toolkit.ui.tema import FUENTE_CODIGO, RIESGO, tarjeta, titulo

Handler = Callable[[], Awaitable[None]]


class PantallaConexion:
    def __init__(
        self,
        al_conectar: Handler,
        al_simular: Handler,
        al_refrescar: Callable[[], None],
        al_abrir_programa: Callable[[Path], Awaitable[None]],
        al_abrir_sesion: Handler,
        programas: Path,
    ) -> None:
        """`programas`: la carpeta `TP3/asm`, que se lista para abrir con un clic."""
        self.puerto = ft.Dropdown(label="Puerto", width=320, dense=True)
        self._aviso = ft.Text(size=12, color=RIESGO["fl"][0])
        self.aviso = ft.Container(
            ft.Row(
                [
                    ft.Icon(ft.Icons.WARNING_AMBER, color=RIESGO["fl"][0], size=18),
                    ft.Container(self._aviso, expand=True),
                ],
            ),
            bgcolor=RIESGO["fl"][1],
            border_radius=8,
            padding=10,
            visible=False,
        )
        self.conectar = ft.FilledButton("Conectar", icon=ft.Icons.LINK, on_click=al_conectar)
        self.simular = ft.OutlinedButton(
            "Usar sin placa (simulado)",
            icon=ft.Icons.COMPUTER,
            on_click=al_simular,
            tooltip="FakeTransport: el modelo del pipeline hace de placa (con riesgos)",
        )
        conexion = tarjeta(
            ft.Text("Paso 1 de 2", size=12, color=ft.Colors.ON_SURFACE_VARIANT),
            titulo("Conectar con la placa"),
            ft.Text(
                "La Basys 3 aparece como un puerto USB serie (COMx en Windows, /dev/ttyUSBx en "
                "Linux). Al conectar se manda un PING: si no responde en 2 s, no es la placa o "
                "no tiene el bitstream.",
                size=12,
            ),
            ft.Row(
                [
                    self.puerto,
                    ft.IconButton(
                        ft.Icons.REFRESH,
                        tooltip="Actualizar la lista de puertos",
                        on_click=lambda _: al_refrescar(),
                    ),
                ]
            ),
            ft.Text(
                "19200 bps · 8 bits · paridad par · 1 bit de stop. Fijo (ADR-002).",
                size=12,
                font_family=FUENTE_CODIGO,
                color=ft.Colors.ON_SURFACE_VARIANT,
            ),
            self.aviso,
            ft.Row([self.conectar, self.simular]),
        )
        self._lista = ft.ListView(spacing=0, height=260)  # recorta lo que no entra
        for ruta in sorted(programas.rglob("*.asm")):
            carpeta = ruta.parent.relative_to(programas).as_posix()

            async def abrir(_: ft.Event[ft.ListTile], ruta: Path = ruta) -> None:
                await al_abrir_programa(ruta)

            self._lista.controls.append(
                ft.ListTile(
                    leading=ft.Icon(
                        ft.Icons.ERROR_OUTLINE if carpeta == "errores" else ft.Icons.DESCRIPTION,
                        size=18,
                    ),
                    title=ft.Text(ruta.name, font_family=FUENTE_CODIGO, size=13),
                    trailing=ft.Text(carpeta, size=12, color=ft.Colors.ON_SURFACE_VARIANT),
                    dense=True,
                    on_click=abrir,
                )
            )
        programas_card = tarjeta(
            ft.Text("Paso 2 de 2", size=12, color=ft.Colors.ON_SURFACE_VARIANT),
            titulo("Elegir un programa"),
            ft.Text(
                "Los programas del TP (TP3/asm). También se puede abrir cualquier .asm desde la "
                "barra (Abrir) o escribir uno en la página Programa.",
                size=12,
            ),
            self._lista,
            ft.OutlinedButton(
                "Abrir una sesión guardada (.json)",
                icon=ft.Icons.HISTORY,
                on_click=al_abrir_sesion,
                tooltip="Una sesión exportada desde Historial: se navega igual, sin placa",
            ),
        )
        self.control = ft.Container(
            ft.Column(
                [conexion, programas_card],
                width=620,
                spacing=16,
                scroll=ft.ScrollMode.AUTO,
            ),
            alignment=ft.Alignment.TOP_CENTER,
            expand=True,
            padding=ft.Padding.only(top=12),
        )

    def poner_puertos(self, puertos: list[str], elegido: str | None) -> None:
        self.puerto.options = [ft.DropdownOption(p) for p in puertos]
        self.puerto.value = elegido
        self.puerto.hint_text = None if puertos else "No se encontró ningún puerto serie"

    def avisar(self, mensaje: str | None) -> None:
        """El último fallo al conectar (None lo oculta)."""
        self.aviso.visible = mensaje is not None
        self._aviso.value = mensaje or ""

    def habilitar(self, ocupado: bool) -> None:
        self.conectar.disabled = self.simular.disabled = ocupado
