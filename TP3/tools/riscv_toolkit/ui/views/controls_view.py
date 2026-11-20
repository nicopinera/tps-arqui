"""Lo que se ve en todas las páginas: barra superior, controles, banner de RUN y barra de
estado (US-501, rediseño con la maqueta)."""

from collections.abc import Awaitable, Callable

import flet as ft

from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.ui.state import Accion
from riscv_toolkit.ui.tema import FUENTE_CODIGO, PELIGRO, RIESGO

PASOS_MAX = 100  # a 19200 bps cada snapshot tarda ~0,1 s: 100 pasos son ~10 s sin poder cortar
SIMULADO = "Simulado (sin placa)"  # "puerto" que usa FakeTransport

Handler = Callable[[], Awaitable[None]]

_ATAJO = {
    Accion.CARGAR: "Ctrl+L",
    Accion.CORRER: "F5",
    Accion.PASO: "F10",
    Accion.ABORTAR: "Esc",
    Accion.RESET: "Ctrl+R",
}


def _boton(clase: type[ft.Button], texto: str, icono: ft.IconData, on_click: Handler) -> ft.Button:
    return clase(texto, icon=icono, on_click=on_click)


class BarraSuperior:
    """Logo, título, el archivo abierto y la píldora de conexión."""

    def __init__(self, al_conexion: Handler) -> None:
        self._archivo = ft.Text(size=12, font_family=FUENTE_CODIGO)
        self._luz = ft.Icon(ft.Icons.CIRCLE, size=10)
        self._conexion = ft.Text(size=12)
        self.boton = ft.TextButton("Conexión", icon=ft.Icons.CABLE, on_click=al_conexion)
        self.control = ft.Container(
            ft.Row(
                [
                    ft.Icon(ft.Icons.MEMORY, color=ft.Colors.PRIMARY),
                    ft.Text("Pipeline RISC-V", weight=ft.FontWeight.W_600, size=16),
                    ft.Container(
                        self._archivo,
                        bgcolor=ft.Colors.SURFACE_CONTAINER_HIGH,
                        border_radius=12,
                        padding=ft.Padding.symmetric(horizontal=10, vertical=2),
                    ),
                    ft.Container(expand=True),
                    ft.Container(
                        ft.Row([self._luz, self._conexion], spacing=6, tight=True),
                        border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
                        border_radius=14,
                        padding=ft.Padding.symmetric(horizontal=10, vertical=3),
                    ),
                    self.boton,
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            padding=ft.Padding.symmetric(horizontal=12, vertical=6),
            bgcolor=ft.Colors.SURFACE_CONTAINER_LOW,
        )

    def mostrar(
        self,
        archivo: str | None,
        con_errores: bool,
        puerto: str | None,
        version: int | None,
        origen: str | None,
    ) -> None:
        """`puerto` None: desconectado. `origen`: el archivo de una sesión reabierta."""
        self._archivo.value = (archivo or "sin archivo") + (" ●" if con_errores else "")
        self._archivo.color = ft.Colors.ERROR if con_errores else None
        if puerto == SIMULADO:
            self._luz.color, texto = RIESGO["fa"][0], "Simulado (--fake) · golden model"
        elif puerto is not None:
            self._luz.color = ft.Colors.PRIMARY
            texto = f"{puerto} · 19200 8E1 · conectado · protocolo v{version}"
        elif origen is not None:
            self._luz.color, texto = RIESGO["ht"][0], f"Sin placa · sesión desde {origen}"
        else:
            self._luz.color, texto = ft.Colors.OUTLINE, "Desconectado"
        self._conexion.value = texto
        self.boton.content = "Desconectar" if puerto is not None else "Conexión"
        self.boton.icon = ft.Icons.LINK_OFF if puerto is not None else ft.Icons.CABLE


class Controles:
    """Abrir y Ensamblar | Cargar, Correr, Paso, Paso xN | Abortar, Reset | ◀ ciclo ▶."""

    def __init__(
        self,
        acciones: dict[Accion, Handler],
        al_pasos: Handler,
        al_abrir: Handler,
        al_ensamblar: Handler,
        al_ir: Callable[[int], None],
    ) -> None:
        """`al_ir(indice)`: mover el cursor del historial (app.py valida el rango)."""
        a = acciones
        self.botones: dict[Accion, ft.Button | ft.OutlinedButton] = {
            Accion.CARGAR: _boton(
                ft.FilledTonalButton, "Cargar", ft.Icons.UPLOAD, a[Accion.CARGAR]
            ),
            Accion.CORRER: _boton(ft.FilledButton, "Correr", ft.Icons.PLAY_ARROW, a[Accion.CORRER]),
            Accion.PASO: _boton(ft.FilledTonalButton, "Paso", ft.Icons.REDO, a[Accion.PASO]),
            Accion.ABORTAR: _boton(ft.FilledButton, "Abortar", ft.Icons.STOP, a[Accion.ABORTAR]),
            Accion.RESET: ft.OutlinedButton(
                "Reset", icon=ft.Icons.RESTART_ALT, on_click=a[Accion.RESET]
            ),
        }
        for accion, boton in self.botones.items():
            boton.tooltip = _ATAJO[accion]
        self.n = ft.TextField(
            value="10",
            width=56,
            dense=True,
            input_filter=ft.NumbersOnlyInputFilter(),
            text_align=ft.TextAlign.CENTER,
            tooltip="N",
        )
        self.boton_pasos = _boton(ft.FilledTonalButton, "Paso xN", ft.Icons.FAST_FORWARD, al_pasos)
        self.abrir = ft.TextButton(
            "Abrir", icon=ft.Icons.FOLDER_OPEN, on_click=al_abrir, tooltip="Ctrl+O"
        )
        self.ensamblar = ft.TextButton(
            "Ensamblar", icon=ft.Icons.BUILD, on_click=al_ensamblar, tooltip="Ctrl+B"
        )
        self._indice = self._total = 0
        self.anterior = ft.IconButton(
            ft.Icons.CHEVRON_LEFT,
            tooltip="Ciclo anterior",
            on_click=lambda _: al_ir(self._indice - 1),
        )
        self.siguiente = ft.IconButton(
            ft.Icons.CHEVRON_RIGHT,
            tooltip="Ciclo siguiente",
            on_click=lambda _: al_ir(self._indice + 1),
        )
        self._ciclo = ft.Text(size=12, font_family=FUENTE_CODIGO)
        self._modo = ft.Text(size=11, weight=ft.FontWeight.W_600)
        self._chip = ft.Container(
            self._modo,
            border_radius=10,
            padding=ft.Padding.symmetric(horizontal=8, vertical=2),
            on_click=lambda _: al_ir(self._total - 1),
            tooltip="Volver al ciclo actual",
        )
        b = self.botones
        separador = ft.VerticalDivider(width=12)
        self.control = ft.Row(
            [
                self.abrir,
                self.ensamblar,
                separador,
                b[Accion.CARGAR],
                b[Accion.CORRER],
                b[Accion.PASO],
                self.boton_pasos,
                self.n,
                separador,
                b[Accion.ABORTAR],
                b[Accion.RESET],
                ft.Container(expand=True),
                self.anterior,
                self._ciclo,
                self.siguiente,
                self._chip,
            ],
            spacing=6,
            height=40,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        )

    def pasos(self) -> int:
        """N del campo, acotado a 1…PASOS_MAX (el campo solo acepta dígitos)."""
        return max(1, min(int(self.n.value or 1), PASOS_MAX))

    def habilitar(self, habilitadas: frozenset[Accion], por_que_no_cargar: str | None) -> None:
        """Copia el resultado de `acciones_habilitadas`: la regla no vive acá (AC3)."""
        for accion, boton in self.botones.items():
            boton.disabled = accion not in habilitadas
        self.boton_pasos.disabled = self.n.disabled = Accion.PASO not in habilitadas
        abortar = self.botones[Accion.ABORTAR]
        texto, fondo = PELIGRO
        activo = not abortar.disabled
        abortar.style = ft.ButtonStyle(
            bgcolor=fondo if activo else None, color=texto if activo else None
        )
        cargar = self.botones[Accion.CARGAR]
        cargar.tooltip = por_que_no_cargar if cargar.disabled and por_que_no_cargar else "Ctrl+L"

    def mostrar_ciclo(self, indice: int, total: int, ciclo: int | None, ocupado: bool) -> None:
        self._indice, self._total = indice, total
        navegable = total > 1 and not ocupado  # mientras opera, la sesión mueve el cursor
        self.anterior.disabled = not navegable or indice <= 0
        self.siguiente.disabled = not navegable or indice >= total - 1
        # El ciclo de la DU y en qué snapshot se está: después de un RUN no coinciden.
        self._ciclo.value = (
            f"Ciclo {ciclo} · {indice + 1}/{total}" if ciclo is not None else "Sin ciclos"
        )
        en_vivo = indice >= total - 1
        self._modo.value = "En vivo" if en_vivo else "Revisando"
        self._chip.bgcolor = (
            ft.Colors.PRIMARY_CONTAINER if en_vivo else ft.Colors.TERTIARY_CONTAINER
        )
        self._chip.visible = total > 0


class BannerRun:
    """Mientras corre en la placa: cuánto hace, una barra indeterminada y Abortar."""

    def __init__(self, al_abortar: Handler) -> None:
        self._texto = ft.Text(size=13)
        texto, fondo = PELIGRO
        self.control = ft.Container(
            ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(ft.Icons.DIRECTIONS_RUN, color=ft.Colors.PRIMARY),
                            ft.Container(self._texto, expand=True),
                            ft.FilledButton(
                                "Abortar",
                                icon=ft.Icons.STOP,
                                on_click=al_abortar,
                                tooltip="Esc",
                                style=ft.ButtonStyle(bgcolor=fondo, color=texto),
                            ),
                        ],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.ProgressBar(),
                ],
                spacing=6,
            ),
            bgcolor=ft.Colors.PRIMARY_CONTAINER,
            border_radius=10,
            padding=10,
            visible=False,
        )

    def mostrar(self, segundos: int | None) -> None:
        """None: no hay un RUN en curso."""
        self.control.visible = segundos is not None
        self._texto.value = (
            f"Corriendo en la placa desde hace {segundos} s. En RUN la placa no informa ciclo "
            "por ciclo: esperando el snapshot final…"
        )


# Insignia de la barra de estado: estado → (texto, fondo, color del texto).
_INSIGNIA: dict[EstadoDU | None, tuple[ft.Colors, ft.Colors]] = {
    EstadoDU.RUN: (ft.Colors.PRIMARY, ft.Colors.ON_PRIMARY),
    EstadoDU.STEPPING: (ft.Colors.PRIMARY_CONTAINER, ft.Colors.ON_PRIMARY_CONTAINER),
    EstadoDU.READY: (ft.Colors.SECONDARY_CONTAINER, ft.Colors.ON_SECONDARY_CONTAINER),
    EstadoDU.HALTED: (ft.Colors.TERTIARY_CONTAINER, ft.Colors.ON_TERTIARY_CONTAINER),
}


class BarraEstado:
    """La insignia del estado de la DU, motivo, ciclo, PC y riesgos acumulados."""

    def __init__(self) -> None:
        self._estado = ft.Text(size=11, weight=ft.FontWeight.W_600)
        self._insignia = ft.Container(
            self._estado, border_radius=4, padding=ft.Padding.symmetric(horizontal=8, vertical=2)
        )
        self._texto = ft.Text(font_family=FUENTE_CODIGO, size=12)
        self.control = ft.Container(
            ft.Row([self._insignia, self._texto], spacing=12),
            padding=ft.Padding.symmetric(horizontal=12, vertical=5),
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
        )

    def mostrar(
        self,
        estado: EstadoDU | None,
        conectado: bool,
        guardada: bool,
        snapshot: Snapshot | None,
        riesgos: tuple[int, int, int],
        ocupado: bool,
    ) -> None:
        """`guardada`: se está viendo una sesión reabierta, sin placa."""
        if guardada:
            nombre = "SESIÓN GUARDADA"
        elif not conectado:
            nombre = "SIN CONEXIÓN"
        else:
            nombre = estado.name if estado is not None else "—"
        fondo, color = _INSIGNIA.get(
            estado if conectado or guardada else None,
            (ft.Colors.SURFACE_CONTAINER_LOW, ft.Colors.ON_SURFACE_VARIANT),
        )
        self._estado.value, self._estado.color, self._insignia.bgcolor = nombre, color, fondo
        partes = []
        if snapshot is not None:
            motivo = snapshot.motivo.name if snapshot.motivo is not None else "—"
            stalls, flushes, fwds = riesgos
            partes += [
                f"Motivo {motivo}",
                f"Ciclo {snapshot.ciclos}",
                f"PC 0x{snapshot.pc:08x}",
                f"Stalls {stalls}",
                f"Flushes {flushes}",
                f"Forwardings {fwds}",
            ]
        if ocupado and estado is not EstadoDU.RUN:
            partes.append("esperando a la placa…")
        self._texto.value = "  ·  ".join(partes)
