"""GUI de escritorio del TP3 (US-501, ADR-012): arma la ventana y conecta las vistas con la
sesión.

Es la única capa que importa Flet (PRD §4.3), y este módulo es el único que decide el
transporte (placa o `FakeTransport`). Las reglas (qué botón se habilita, qué línea se resalta)
están en `state.py`; las vistas solo muestran.

Concurrencia: Flet atiende los eventos en un solo hilo (el bucle de asyncio). Cada operación
con la placa corre en otro hilo con `await asyncio.to_thread(...)`, así la ventana nunca se
congela. Reglas:
- la sesión solo la usa el hilo de la operación en curso, y hay una sola a la vez
  (`EstadoUI.ocupado` deshabilita todo lo demás);
- Flet solo se toca desde el bucle: el código que sigue al `await` corre ahí;
- lo único que cruza entre hilos es el `threading.Event` con el que Abortar le pide al RUN
  que termine (cancelación cooperativa, `DebugSession.run`).
"""

import asyncio
import threading
from collections.abc import Awaitable, Callable
from contextlib import suppress
from dataclasses import replace
from pathlib import Path

import flet as ft

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.protocol.codec import ErrorTrama
from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import (
    ErrorPuerto,
    SerialTransport,
    detectar_puerto,
    listar_puertos,
)
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.session.debug_session import DebugSession, ErrorNackDU, ErrorSesion
from riscv_toolkit.ui.pipeline import columnas_pipeline
from riscv_toolkit.ui.state import (
    Accion,
    EstadoUI,
    acciones_habilitadas,
    contar_riesgos,
    pc_resaltado,
)
from riscv_toolkit.ui.tema import ASSETS, FUENTES, tema
from riscv_toolkit.ui.views.connection_bar import SIMULADO, BarraConexion
from riscv_toolkit.ui.views.controls_view import BarraEstado, Controles
from riscv_toolkit.ui.views.editor_view import PanelPrograma
from riscv_toolkit.ui.views.latch_detail_view import DetalleLatch
from riscv_toolkit.ui.views.pipeline_view import VistaPipeline

ASM = Path(__file__).resolve().parents[3] / "asm"  # TP3/asm: donde abrir y guardar
# Lo que puede fallar al hablar con la placa: NACK, respuesta inesperada, basura, puerto
# (OSError incluye TimeoutError y los errores de pyserial, como desenchufar el cable).
_ERRORES = (ErrorSesion, ErrorTrama, ErrorPuerto, OSError)
_ESPERA_CIERRE = 5.0  # s: al cerrar la ventana, cuánto esperar a que termine la operación


class App:
    """El controlador: recibe los eventos de las vistas, habla con la sesión y refresca."""

    def __init__(self, page: ft.Page, fake: bool) -> None:
        self.page = page
        self.estado = EstadoUI()
        self.sesion: DebugSession | None = None
        self.version: int | None = None  # la de PING
        self.puerto: str | None = None  # al que se está conectado
        self.imagen: Imagen | None = None  # la última ensamblada sin errores (la del listado)
        self.texto_imagen = ""  # el texto del que salió `imagen`
        self.cargada: Imagen | None = None  # la que está en la placa
        self.ruta: Path | None = None  # el .asm abierto
        self.cancelar: threading.Event | None = None  # el del RUN en curso, si hay uno
        # Lo último que se leyó de la sesión: mientras hay una operación en curso la sesión
        # es del worker, y la barra de estado sigue mostrando esto.
        self._snapshot: Snapshot | None = None
        self._riesgos = (0, 0)

        self.picker = ft.FilePicker()
        page.services.append(self.picker)
        self.barra = BarraConexion(self.conectar, self.buscar_puertos)
        self.acciones: dict[Accion, Callable[[], Awaitable[None]]] = {
            Accion.CARGAR: self.cargar,
            Accion.CORRER: self.correr,
            Accion.PASO: self.paso,
            Accion.ABORTAR: self.abortar,
            Accion.RESET: self.reset,
        }
        self.controles = Controles(self.acciones, self.pasos)
        self.panel = PanelPrograma(
            self.abrir, self.guardar, self.al_ensamblar, self.editado, self.refrescar
        )
        self.detalle = DetalleLatch(self.refrescar)
        self.pipeline = VistaPipeline(self.elegir_latch)
        self.barra_estado = BarraEstado()
        # Las páginas del menú lateral; los controles y las barras se comparten.
        self.paginas: list[tuple[str, ft.IconData, ft.Control]] = [
            ("Programa", ft.Icons.CODE, self.panel.control),
            (
                "Pipeline",
                ft.Icons.VIEW_COLUMN,
                ft.Column(
                    [self.pipeline.control, ft.Divider(height=1), self.detalle.control],
                    scroll=ft.ScrollMode.AUTO,
                    expand=True,
                ),
            ),
        ]
        self.cuerpo = ft.Container(self.panel.control, expand=True)
        self.buscar_puertos(SIMULADO if fake else None)

    # --- Armado ----------------------------------------------------------------------------

    def armar(self) -> None:
        page = self.page
        page.title = "RISC-V TP3 - Debug Unit"
        page.theme_mode = ft.ThemeMode.LIGHT
        page.fonts = FUENTES
        page.theme = tema()
        page.padding = 0
        page.spacing = 0
        page.horizontal_alignment = ft.CrossAxisAlignment.STRETCH  # barra de estado a lo ancho
        page.on_keyboard_event = self.tecla
        page.window.prevent_close = True  # para abortar un RUN antes de cerrar
        page.window.on_event = self.ventana

        menu = ft.NavigationRail(
            selected_index=0,
            label_type=ft.NavigationRailLabelType.ALL,
            destinations=[
                ft.NavigationRailDestination(icon=icono, label=nombre)
                for nombre, icono, _ in self.paginas
            ],
            on_change=lambda e: self.ir_a_pagina(e.control.selected_index),
        )
        contenido = ft.Column(
            [self.barra.control, ft.Divider(height=1), self.controles.control, self.cuerpo],
            expand=True,
        )
        page.add(
            ft.Row(
                [
                    menu,
                    ft.VerticalDivider(width=1),
                    ft.Container(contenido, expand=True, padding=12),
                ],
                expand=True,
            ),
            self.barra_estado.control,
        )
        self.refrescar()

    # --- Refresco: el estado se copia a las vistas -----------------------------------------

    def refrescar(self) -> None:
        """Copia el estado a todos los controles. Se llama después de cada cambio."""
        if self.sesion is not None and not self.estado.ocupado:
            self._snapshot = self.sesion.historial.actual
            self._riesgos = contar_riesgos(self.sesion.historial)
        self.controles.habilitar(acciones_habilitadas(self.estado))
        self.barra.mostrar(
            self.estado.conectado, self.puerto == SIMULADO, self.version, self.puerto
        )
        self.barra.boton.disabled = self.estado.ocupado
        self.barra_estado.mostrar(
            self.estado.estado_du, self._snapshot, self._riesgos, self.estado.ocupado
        )
        self.panel.resaltar(self._pc_resaltado())
        imem = self.cargada.palabras if self.cargada is not None else None
        self.pipeline.mostrar(
            columnas_pipeline(self._snapshot, imem) if self._snapshot is not None else None,
            self.detalle.elegido(),
        )
        self.detalle.mostrar(self._snapshot)
        self.page.update()

    def ir_a_pagina(self, indice: int) -> None:
        self.cuerpo.content = self.paginas[indice][2]
        self.page.update()

    def elegir_latch(self, nombre: str) -> None:
        """Clic en una etapa del pipeline: muestra el latch que guarda su instrucción."""
        self.detalle.elegir(nombre)
        self.refrescar()

    def _pc_resaltado(self) -> int | None:
        """La línea a resaltar, solo si el listado es del programa que está en la placa."""
        if self._snapshot is None or self.cargada is None or self.cargada is not self.imagen:
            return None
        return pc_resaltado(self._snapshot, self.panel.etapa_elegida())

    def _avisar(self, mensaje: str) -> None:
        self.page.show_dialog(ft.SnackBar(ft.Text(mensaje), show_close_icon=True))

    def _puede(self, accion: Accion) -> bool:
        return accion in acciones_habilitadas(self.estado)

    # --- Operaciones con la placa ----------------------------------------------------------

    async def _ejecutar(
        self, operacion: Callable[[], object], durante: EstadoDU | None = None
    ) -> bool:
        """Corre `operacion` (que usa la sesión) en otro hilo. False si falló (ya avisó).

        `durante`: el estado de la DU mientras corre (RUN, para que se habilite Abortar).
        """
        self.estado = replace(self.estado, ocupado=True, estado_du=durante or self.estado.estado_du)
        self.refrescar()
        try:
            await asyncio.to_thread(operacion)
            ok = True
        except _ERRORES as error:
            self._avisar(str(error))
            ok = False
        finally:
            estado_du = self.sesion.estado if self.sesion is not None else None
            self.estado = replace(self.estado, ocupado=False, estado_du=estado_du)
            self.refrescar()
        pc = self._pc_resaltado()
        # Solo si el listado está en pantalla: un scroll_to a un control desmontado hace que
        # Flet cierre la sesión (el cliente reconecta y main() arranca de cero).
        if pc is not None and self.cuerpo.content is self.panel.control:
            with suppress(Exception):  # el scroll es cosmético: que nunca tape el resultado
                await self.panel.mostrar_fila(pc)
        return ok

    async def conectar(self) -> None:
        """Conectar (PING + DUMP para saber el estado) o, si ya está, desconectar."""
        if self.estado.conectado:
            self._desconectar()
            return
        puerto = self.barra.puerto.value
        if not puerto:
            self._avisar("Elegí un puerto (o la opción simulada).")
            return

        def abrir() -> None:
            transporte = FakeTransport() if puerto == SIMULADO else SerialTransport(puerto)
            sesion = DebugSession(transporte)
            try:
                self.version = sesion.conectar()
                with suppress(ErrorNackDU):  # en RUN el DUMP se rechaza, y eso dice el estado
                    sesion.dump()
            except BaseException:
                sesion.close()
                raise
            self.sesion = sesion

        self.puerto = puerto
        if await self._ejecutar(abrir):
            self.estado = replace(self.estado, conectado=True)
            self.refrescar()

    def _desconectar(self) -> None:
        if self.sesion is not None:
            self.sesion.close()
        self.sesion = self.version = self.cargada = self._snapshot = None
        self._riesgos = (0, 0)
        self.estado = EstadoUI(imagen_valida=self.estado.imagen_valida)
        self.refrescar()

    def buscar_puertos(self, preferido: str | None = None) -> None:
        """Llena el desplegable y preselecciona la Basys 3 si la encuentra."""
        puertos = listar_puertos()
        if preferido is None:
            try:
                preferido = detectar_puerto()
            except ErrorPuerto:
                preferido = puertos[0] if puertos else SIMULADO
        self.barra.poner_puertos(puertos, preferido)

    async def cargar(self) -> None:
        sesion, imagen = self.sesion, self.imagen
        if sesion is None or imagen is None or not self._puede(Accion.CARGAR):
            return

        def operacion() -> None:
            sesion.load(imagen.palabras)
            self.cargada = imagen
            sesion.dump()  # ciclo 0: muestra el estado inicial y resalta la primera línea

        await self._ejecutar(operacion)

    async def correr(self) -> None:
        sesion = self.sesion
        if sesion is None or not self._puede(Accion.CORRER):
            return
        self.cancelar = cancelar = threading.Event()  # uno nuevo por RUN: nunca queda levantado
        try:
            await self._ejecutar(lambda: sesion.run(cancelar), durante=EstadoDU.RUN)
        finally:
            self.cancelar = None

    async def paso(self) -> None:
        if self.sesion is not None and self._puede(Accion.PASO):
            await self._ejecutar(self.sesion.step)

    async def pasos(self) -> None:
        sesion = self.sesion
        if sesion is None or not self._puede(Accion.PASO):
            return
        n = self.controles.pasos()

        def operacion() -> None:
            for _ in range(n):
                if sesion.step().motivo is not None:  # terminó: los que faltan darían NACK
                    return

        await self._ejecutar(operacion)

    async def abortar(self) -> None:
        sesion = self.sesion
        if sesion is None or not self._puede(Accion.ABORTAR):
            return
        if self.cancelar is not None:
            self.cancelar.set()  # hay un RUN nuestro esperando: que mande el ABORT él
        else:  # la DU estaba en RUN al conectar: no hay nadie esperando
            await self._ejecutar(sesion.abort)

    async def reset(self) -> None:
        sesion = self.sesion
        if sesion is None or not self._puede(Accion.RESET):
            return

        def operacion() -> None:
            sesion.reset()
            sesion.dump()

        await self._ejecutar(operacion)

    # --- Programa --------------------------------------------------------------------------

    def al_ensamblar(self) -> None:
        """Ensambla el editor. Con error: lo muestra y Cargar queda deshabilitado (AC2).

        Si falla, el listado anterior se queda: puede ser el del programa que está en la placa,
        y sigue sirviendo para seguir la ejecución.
        """
        texto = self.panel.editor.value or ""
        try:
            imagen = ensamblar(texto)
        except ErrorEnsamblado as error:
            self.panel.mostrar_mensajes((error.linea, error.mensaje), [], self.panel.ir_a_linea)
            self.estado = replace(self.estado, imagen_valida=False)
        else:
            self.imagen, self.texto_imagen = imagen, texto
            self.panel.mostrar_mensajes(None, imagen.advertencias, self.panel.ir_a_linea)
            self.panel.mostrar_listado(imagen, texto)
            self.estado = replace(self.estado, imagen_valida=True)
        self.refrescar()

    def editado(self) -> None:
        """Si el texto ya no es el que se ensambló, no se puede cargar hasta reensamblar."""
        if self.estado.imagen_valida and self.panel.editor.value != self.texto_imagen:
            self.estado = replace(self.estado, imagen_valida=False)
            self.refrescar()

    async def abrir(self) -> None:
        archivos = await self.picker.pick_files(
            dialog_title="Abrir programa",
            initial_directory=str(ASM),
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["asm", "s"],
        )
        if not archivos or archivos[0].path is None:
            return
        ruta = Path(archivos[0].path)
        try:
            texto = ruta.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            self._avisar(f"No se pudo abrir {ruta.name}: {error}")
            return
        self.ruta = ruta
        self.panel.editor.value = texto
        self.panel.poner_archivo(ruta.name)
        self.editado()
        self.refrescar()

    async def guardar(self) -> None:
        ruta = self.ruta
        if ruta is None:
            elegido = await self.picker.save_file(
                dialog_title="Guardar programa",
                initial_directory=str(ASM),
                file_name="programa.asm",
                file_type=ft.FilePickerFileType.CUSTOM,
                allowed_extensions=["asm"],
            )
            if not elegido:
                return
            ruta = Path(elegido)
        try:
            ruta.write_text(self.panel.editor.value or "", encoding="utf-8")
        except OSError as error:
            self._avisar(f"No se pudo guardar {ruta.name}: {error}")
            return
        self.ruta = ruta
        self.panel.poner_archivo(ruta.name)
        self._avisar(f"Guardado en {ruta}")
        self.refrescar()

    # --- Teclado y ventana -----------------------------------------------------------------

    async def tecla(self, e: ft.KeyboardEvent) -> None:
        """Atajos. Cada acción revisa `acciones_habilitadas`: un atajo no saltea a un botón
        deshabilitado (AC3)."""
        atajos: dict[tuple[str, bool, bool], Callable[[], Awaitable[None]]] = {
            ("F5", False, False): self.correr,
            ("F5", False, True): self.abortar,
            ("F10", False, False): self.paso,
            ("L", True, False): self.cargar,
            ("R", True, False): self.reset,
            ("O", True, False): self.abrir,
            ("S", True, False): self.guardar,
        }
        combinacion = (e.key, e.ctrl, e.shift)
        if combinacion == ("B", True, False):
            self.al_ensamblar()
        elif combinacion in atajos:
            await atajos[combinacion]()

    async def ventana(self, e: ft.WindowEvent[ft.Window]) -> None:
        """Al cerrar: aborta el RUN en curso (si no, el hilo esperaría para siempre y la placa
        quedaría corriendo), espera a la operación y cierra el puerto."""
        if e.type is not ft.WindowEventType.CLOSE:
            return
        if self.cancelar is not None:
            self.cancelar.set()
        for _ in range(int(_ESPERA_CIERRE / 0.1)):
            if not self.estado.ocupado:
                break
            await asyncio.sleep(0.1)
        if self.sesion is not None and not self.estado.ocupado:
            self.sesion.close()
        await self.page.window.destroy()


def main(fake: bool = False) -> int:
    """Abre la ventana y bloquea hasta que se cierra. `fake`: preelige el modo simulado."""
    ft.run(lambda page: App(page, fake).armar(), assets_dir=str(ASSETS))
    return 0
