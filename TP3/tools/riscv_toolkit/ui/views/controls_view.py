"""Controles de ejecución y barra de estado (US-501)."""

from collections.abc import Awaitable, Callable

import flet as ft

from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.ui.state import Accion
from riscv_toolkit.ui.tema import FUENTE_CODIGO

PASOS_MAX = 100  # a 19200 bps cada snapshot tarda ~0,1 s: 100 pasos son ~10 s sin poder cortar

Handler = Callable[[], Awaitable[None]]

# Texto, ícono y atajo de cada botón. Los atajos los atiende app.py (`ATAJOS`).
_BOTONES = {
    Accion.CARGAR: ("Cargar", ft.Icons.UPLOAD, "Ctrl+L"),
    Accion.CORRER: ("Correr", ft.Icons.PLAY_ARROW, "F5"),
    Accion.PASO: ("Paso", ft.Icons.REDO, "F10"),
    Accion.ABORTAR: ("Abortar", ft.Icons.STOP, "Shift+F5"),
    Accion.RESET: ("Reset", ft.Icons.RESTART_ALT, "Ctrl+R"),
}


class Controles:
    """Una fila de botones; cada uno llama a `acciones[accion]` (en app.py)."""

    def __init__(self, acciones: dict[Accion, Handler], al_pasos: Handler) -> None:
        self.botones = {
            accion: ft.OutlinedButton(
                texto, icon=icono, tooltip=f"{texto} ({atajo})", on_click=acciones[accion]
            )
            for accion, (texto, icono, atajo) in _BOTONES.items()
        }
        self.n = ft.TextField(
            value="10",
            width=70,
            dense=True,
            label="N",
            input_filter=ft.NumbersOnlyInputFilter(),
        )
        self.boton_pasos = ft.OutlinedButton(
            "Paso xN", icon=ft.Icons.FAST_FORWARD, on_click=al_pasos
        )
        b = self.botones
        self.control = ft.Row(
            [
                b[Accion.CARGAR],
                b[Accion.CORRER],
                b[Accion.PASO],
                self.n,
                self.boton_pasos,
                b[Accion.ABORTAR],
                b[Accion.RESET],
            ],
            wrap=True,
        )

    def pasos(self) -> int:
        """N del campo, acotado a 1…PASOS_MAX (el campo solo acepta dígitos)."""
        return max(1, min(int(self.n.value or 1), PASOS_MAX))

    def habilitar(self, habilitadas: frozenset[Accion]) -> None:
        """Copia el resultado de `acciones_habilitadas`: la regla no vive acá (AC3)."""
        for accion, boton in self.botones.items():
            boton.disabled = accion not in habilitadas
        self.boton_pasos.disabled = Accion.PASO not in habilitadas
        self.n.disabled = self.boton_pasos.disabled


class BarraEstado:
    """Estado de la DU, motivo, ciclo, PC y riesgos acumulados."""

    def __init__(self) -> None:
        self._texto = ft.Text(font_family=FUENTE_CODIGO, size=12)
        self.control = ft.Container(
            self._texto,
            padding=ft.Padding.symmetric(horizontal=12, vertical=6),
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
        )

    def mostrar(
        self,
        estado: EstadoDU | None,
        snapshot: Snapshot | None,
        riesgos: tuple[int, int],
        ocupado: bool,
    ) -> None:
        partes = [f"Estado: {estado.name if estado is not None else '—'}"]
        if snapshot is not None:
            motivo = snapshot.motivo.name if snapshot.motivo is not None else "—"
            partes += [
                f"Motivo: {motivo}",
                f"Ciclo: {snapshot.ciclos}",
                f"PC: 0x{snapshot.pc:08x}",
                f"Stalls: {riesgos[0]}",
                f"Flushes: {riesgos[1]}",
            ]
        if ocupado:
            partes.append("esperando a la placa…")
        self._texto.value = "  ·  ".join(partes)
