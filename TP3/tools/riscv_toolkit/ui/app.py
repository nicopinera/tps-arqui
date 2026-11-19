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
import time
from collections.abc import Awaitable, Callable
from contextlib import suppress
from dataclasses import replace
from pathlib import Path

import flet as ft

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.protocol.codec import ErrorTrama
from riscv_toolkit.protocol.comandos import EstadoDU, Motivo
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import (
    ErrorPuerto,
    SerialTransport,
    detectar_puerto,
    listar_puertos,
)
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.session.debug_session import DebugSession, ErrorNackDU, ErrorSesion
from riscv_toolkit.session.export import ErrorSesionGuardada, exportar, leer
from riscv_toolkit.session.history import SnapshotHistory
from riscv_toolkit.session.verificar import comparacion, esperado_de
from riscv_toolkit.ui.arquitectura import filas_memoria, filas_registros, rango_desde_hasta
from riscv_toolkit.ui.historial import (
    cambios_registros,
    escribe_al_final,
    filas_historial,
    origen_de,
    resumen,
    ultimas_escrituras,
)
from riscv_toolkit.ui.pipeline import columnas_pipeline
from riscv_toolkit.ui.pipeline_chart import carta_pipeline
from riscv_toolkit.ui.state import (
    Accion,
    EstadoUI,
    acciones_habilitadas,
    contar_riesgos,
    pc_resaltado,
)
from riscv_toolkit.ui.tema import ASSETS, FUENTES, tema
from riscv_toolkit.ui.views.connect_view import PantallaConexion
from riscv_toolkit.ui.views.controls_view import (
    SIMULADO,
    BannerRun,
    BarraEstado,
    BarraSuperior,
    Controles,
)
from riscv_toolkit.ui.views.editor_view import PanelPrograma
from riscv_toolkit.ui.views.memory_view import VistaMemoria
from riscv_toolkit.ui.views.pipeline_chart_view import MAX_CICLOS, VistaCarta
from riscv_toolkit.ui.views.pipeline_view import PaginaPipeline
from riscv_toolkit.ui.views.registers_view import VistaRegistros
from riscv_toolkit.ui.views.summary_view import VistaResumen
from riscv_toolkit.ui.views.timeline_view import VistaHistorial
from riscv_toolkit.ui.views.verify_view import Verificacion, VistaVerificar

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
        self.con_error = False  # el último Ensamblar dio error
        self.cargada: Imagen | None = None  # la que está en la placa
        self.ruta: Path | None = None  # el .asm abierto
        self.cancelar: threading.Event | None = None  # el del RUN en curso, si hay uno
        self._run_desde: float | None = None  # time.monotonic() al empezar el RUN en curso
        # Lo último que se leyó de la sesión: mientras hay una operación en curso la sesión
        # es del worker, y la barra de estado sigue mostrando esto.
        self._snapshot: Snapshot | None = None
        self._anterior: Snapshot | None = None  # el de antes en el historial: contra él se resalta
        self._riesgos = (0, 0, 0)
        self._pedido: tuple[int, dict[int, int]] | None = None  # DUMP_MEM: (ciclo, memoria)
        self.fuente_cargada: str | None = None  # el texto del programa de la placa (o reabierto)
        # Una sesión reabierta (US-505): su historial y su programa, sin placa.
        self.abierta: SnapshotHistory | None = None
        self.origen: str | None = None  # el nombre de su archivo
        self.programa_abierto: list[int] | None = None
        self._verificacion: Verificacion | str | None = None
        self.editando = True  # Programa: el editor (True) o la fuente en ejecución
        self._ultimo_error = ""  # el de la última operación que falló

        self.picker = ft.FilePicker()
        page.services.append(self.picker)
        self.acciones: dict[Accion, Callable[[], Awaitable[None]]] = {
            Accion.CARGAR: self.cargar,
            Accion.CORRER: self.correr,
            Accion.PASO: self.paso,
            Accion.ABORTAR: self.abortar,
            Accion.RESET: self.reset,
        }
        self.barra = BarraSuperior(self.boton_conexion)
        self.conexion = PantallaConexion(
            self.conectar, self.simular, self.buscar_puertos, self.abrir_ruta,
            self.reabrir_sesion, ASM,
        )  # fmt: skip
        self.controles = Controles(
            self.acciones, self.pasos, self.abrir, self._ensamblar_boton, self.ir_a_ciclo
        )
        self.banner = BannerRun(self.abortar)
        self.panel = PanelPrograma(self.guardar, self.editado, self.refrescar, self.cambiar_modo)
        self.pipeline = PaginaPipeline(self.refrescar)
        self.carta = VistaCarta(self.ir_a_ciclo)
        self.registros = VistaRegistros(self.refrescar)
        self.memoria = VistaMemoria(self.leer_memoria)
        self.historial = VistaHistorial(self.ir_a_ciclo, self.exportar_sesion, self.reabrir_sesion)
        self.verificacion = VistaVerificar(self.verificar, self.ir_a_ciclo)
        self.resumen = VistaResumen()
        self.barra_estado = BarraEstado()
        # Las páginas del menú lateral; la barra superior, los controles y la barra de estado
        # se comparten. La pantalla de conexión no está en el menú: es el botón Conexión.
        self.paginas: list[tuple[str, ft.IconData, ft.Control]] = [
            ("Programa", ft.Icons.CODE, self.panel.control),
            ("Pipeline", ft.Icons.VIEW_COLUMN, self.pipeline.control),
            ("Carta", ft.Icons.GRID_ON, self.carta.control),
            ("Registros", ft.Icons.TABLE_ROWS, self.registros.control),
            ("Memoria", ft.Icons.MEMORY, self.memoria.control),
            ("Historial", ft.Icons.HISTORY, self.historial.control),
            ("Verificar", ft.Icons.FACT_CHECK, self.verificacion.control),
            ("Resumen", ft.Icons.INSIGHTS, self.resumen.control),
        ]
        self.menu = ft.NavigationRail(
            selected_index=None,
            label_type=ft.NavigationRailLabelType.ALL,
            destinations=[
                ft.NavigationRailDestination(icon=icono, label=nombre)
                for nombre, icono, _ in self.paginas
            ],
            on_change=lambda e: self.ir_a_pagina(e.control.selected_index),
        )
        self.cuerpo = ft.Container(self.conexion.control, expand=True)
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
        page.horizontal_alignment = ft.CrossAxisAlignment.STRETCH  # barras a lo ancho
        page.on_keyboard_event = self.tecla
        page.window.prevent_close = True  # para abortar un RUN antes de cerrar
        page.window.on_event = self.ventana

        contenido = ft.Column(
            [self.controles.control, self.banner.control, self.cuerpo], expand=True
        )
        page.add(
            self.barra.control,
            ft.Divider(height=1),
            ft.Row(
                [
                    self.menu,
                    ft.VerticalDivider(width=1),
                    ft.Container(contenido, expand=True, padding=12),
                ],
                expand=True,
            ),
            self.barra_estado.control,
        )
        self.refrescar()

    # --- Refresco: el estado se copia a las vistas -----------------------------------------

    def _viendo(self, control: ft.Control) -> bool:
        return self.cuerpo.content is control

    def refrescar(self) -> None:
        """Copia el estado a todos los controles. Se llama después de cada cambio.

        Las páginas que recorren el historial entero (carta, historial, resumen, memoria) se
        rearman solo si se están viendo, y no mientras la sesión es del worker.
        """
        h = self._historial()
        e = self.estado
        if h is not None and not e.ocupado:
            self._snapshot = h.actual  # el del cursor: todas las vistas muestran ese ciclo
            self._anterior = list(h)[h.indice - 1] if h.indice > 0 else None
            self._riesgos = contar_riesgos(h)
        snaps = list(h) if h is not None and not e.ocupado else []
        snap = self._snapshot
        motivo_cargar = (
            "No se puede cargar: el programa tiene un error" if self.con_error
            else "Ensamblá el programa primero (Ctrl+B)" if not e.imagen_valida
            else "Conectate a la placa primero" if not e.conectado else None
        )  # fmt: skip
        self.controles.habilitar(acciones_habilitadas(e), motivo_cargar)
        self.controles.mostrar_ciclo(
            h.indice if h is not None else -1,
            len(h) if h is not None else 0,
            snap.ciclos if snap is not None else None,
            e.ocupado,
        )
        self.barra.mostrar(
            self.ruta.name if self.ruta is not None else None,
            self.con_error,
            self.puerto if e.conectado else None,
            self.version,
            self.origen if self.sesion is None else None,
        )
        self.barra.boton.disabled = e.ocupado
        self.conexion.habilitar(e.ocupado or e.conectado)
        self.banner.mostrar(
            int(time.monotonic() - self._run_desde) if self._run_desde is not None else None
        )
        # Sin placa (sesión reabierta) no hay estado en vivo: el del snapshot.
        estado_du = e.estado_du
        if self.sesion is None and snap is not None:
            estado_du = snap.estado
        self.barra_estado.mostrar(
            estado_du, e.conectado, self.sesion is None and self.abierta is not None,
            snap, self._riesgos, e.ocupado,
        )  # fmt: skip
        imem = self._programa()
        columnas = columnas_pipeline(snap, imem) if snap is not None else None
        # Programa: la fuente en ejecución si el listado es el del programa que corre.
        se_puede_ver = self.cargada is not None and self.cargada is self.imagen and snap is not None
        self.panel.mostrar_modo(
            self.editando or not se_puede_ver,
            snap.ciclos if snap is not None else None,
            se_puede_ver,
        )
        etapas: dict[int, list[str]] = {}
        if se_puede_ver and columnas is not None:
            for c in columnas:
                if not c.burbuja and c.pc is not None:
                    etapas.setdefault(c.pc, []).append(c.etapa)
        self.panel.resaltar(self._pc_resaltado(), etapas)
        if self._viendo(self.pipeline.control):
            self.pipeline.mostrar(snap, columnas)
        if self._viendo(self.carta.control) and not e.ocupado:
            visibles = snaps[-MAX_CICLOS:]
            desde = len(snaps) - len(visibles)
            cursor = h.indice - desde if h is not None else None
            self.carta.mostrar(carta_pipeline(visibles, imem), cursor, desde)
        if self._viendo(self.registros.control):
            self.registros.mostrar(
                filas_registros(snap, self._anterior),
                cambios_registros(self._anterior, snap),
                escribe_al_final(snap) if snap is not None else None,
            )
        self.memoria.leer.disabled = not self._puede_leer()
        if self._viendo(self.memoria.control) and not e.ocupado:
            anterior = self._anterior.mem_usada if self._anterior is not None else None
            usada = snap.mem_usada if snap is not None else {}
            pedido = self._pedido
            hasta = h.indice + 1 if h is not None else 0
            self.memoria.mostrar(
                filas_memoria(usada, anterior),
                ultimas_escrituras(snaps[:hasta]),
                (pedido[0], filas_memoria(pedido[1])) if pedido is not None else None,
            )
        if self._viendo(self.historial.control) and not e.ocupado:
            self.historial.mostrar(
                h.indice if h is not None else -1,
                filas_historial(snaps, imem),
                self.origen if self.sesion is None else None,
                e.ocupado,
                not e.conectado,
            )
        self.verificacion.boton.disabled = e.ocupado or not snaps
        self.verificacion.mostrar(self._verificacion)
        if self._viendo(self.resumen.control) and not e.ocupado:
            self.resumen.mostrar(resumen(snaps, imem) if snaps else None)
        self.page.update()

    def ir_a_pagina(self, indice: int | None) -> None:
        if indice is None:
            return
        self.menu.selected_index = indice
        self.cuerpo.content = self.paginas[indice][2]
        self.refrescar()

    def ir_a_conexion(self) -> None:
        self.menu.selected_index = None
        self.cuerpo.content = self.conexion.control
        self.refrescar()

    async def boton_conexion(self) -> None:
        """Barra superior: conectado, desconecta; si no, muestra la pantalla de conexión."""
        if self.estado.conectado:
            self._desconectar()
        self.ir_a_conexion()

    def cambiar_modo(self, editar: bool) -> None:
        self.editando = editar
        self.refrescar()

    def ir_a_ciclo(self, indice: int) -> None:
        """Línea de tiempo: mueve el cursor del historial (solo lectura, AC1)."""
        h = self._historial()
        if h is None or self.estado.ocupado or not 0 <= indice < len(h):
            return
        h.ir_a(indice)
        self.refrescar()

    def _historial(self) -> SnapshotHistory | None:
        """El de la sesión en vivo o, sin placa, el de una sesión reabierta."""
        return self.sesion.historial if self.sesion is not None else self.abierta

    def _programa(self) -> list[int] | None:
        """Las palabras del programa de esta sesión (None si no se sabe)."""
        return self.cargada.palabras if self.cargada is not None else self.programa_abierto

    def _pc_resaltado(self) -> int | None:
        """La línea a resaltar, solo si el listado es del programa que está en la placa."""
        if self._snapshot is None or self.cargada is None or self.cargada is not self.imagen:
            return None
        return pc_resaltado(self._snapshot, self.panel.etapa_elegida())

    def _avisar(self, mensaje: str) -> None:
        self.page.show_dialog(ft.SnackBar(ft.Text(mensaje), show_close_icon=True))

    def _puede(self, accion: Accion) -> bool:
        return accion in acciones_habilitadas(self.estado)

    def _puede_leer(self) -> bool:
        """DUMP_MEM: en cualquier estado menos RUN (protocolo §4.1)."""
        e = self.estado
        return e.conectado and not e.ocupado and e.estado_du is not EstadoDU.RUN

    # --- Operaciones con la placa ----------------------------------------------------------

    async def _ejecutar(
        self, operacion: Callable[[], object], durante: EstadoDU | None = None
    ) -> bool:
        """Corre `operacion` (que usa la sesión) en otro hilo. False si falló (ya avisó).

        `durante`: el estado de la DU mientras corre (RUN, para que se habilite Abortar).
        """
        self.estado = replace(self.estado, ocupado=True, estado_du=durante or self.estado.estado_du)
        self._verificacion = None  # era del estado final de antes
        self.refrescar()
        try:
            await asyncio.to_thread(operacion)
            ok = True
        except _ERRORES as error:
            self._ultimo_error = str(error)
            self._avisar(self._ultimo_error)
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

    async def simular(self) -> None:
        """Usar sin placa: FakeTransport (el golden model contesta como la DU)."""
        await self._conectar_a(SIMULADO)

    async def conectar(self) -> None:
        puerto = self.conexion.puerto.value
        if not puerto:
            self.conexion.avisar("Elegí un puerto, o usá el modo sin placa.")
            self.refrescar()
            return
        await self._conectar_a(puerto)

    async def _conectar_a(self, puerto: str) -> None:
        """PING + DUMP para saber el estado. Si falla, el aviso queda en la pantalla."""
        if self.estado.conectado:
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
            self.abierta = self.origen = self.programa_abierto = None  # manda la placa
            self.conexion.avisar(None)
            self.ir_a_pagina(0)
        else:
            self.conexion.avisar(f"{puerto}: {self._ultimo_error}")
            self.refrescar()

    def _desconectar(self) -> None:
        if self.sesion is not None:
            self.sesion.close()
        self.sesion = self.version = self.cargada = self._snapshot = self._anterior = None
        self._pedido = self.fuente_cargada = self._verificacion = None
        self._riesgos = (0, 0, 0)
        self.estado = EstadoUI(imagen_valida=self.estado.imagen_valida)
        self.refrescar()

    def buscar_puertos(self, preferido: str | None = None) -> None:
        """Llena el desplegable y preselecciona la Basys 3 si la encuentra."""
        puertos = listar_puertos()
        if preferido is None:
            try:
                preferido = detectar_puerto()
            except ErrorPuerto:
                preferido = puertos[0] if puertos else None
        self.conexion.poner_puertos(puertos, preferido if preferido != SIMULADO else None)

    async def cargar(self) -> None:
        sesion, imagen = self.sesion, self.imagen
        if sesion is None or imagen is None or not self._puede(Accion.CARGAR):
            return

        self._pedido = None  # era de otro programa

        def operacion() -> None:
            sesion.load(imagen.palabras)
            self.cargada, self.fuente_cargada = imagen, self.texto_imagen
            sesion.dump()  # ciclo 0: muestra el estado inicial y resalta la primera línea

        if await self._ejecutar(operacion):
            self.editando = False  # la página Programa muestra la fuente en ejecución
            self.refrescar()

    async def correr(self) -> None:
        sesion = self.sesion
        if sesion is None or not self._puede(Accion.CORRER):
            return
        self.cancelar = cancelar = threading.Event()  # uno nuevo por RUN: nunca queda levantado
        self._run_desde = time.monotonic()
        reloj = asyncio.create_task(self._reloj())
        try:
            await self._ejecutar(lambda: sesion.run(cancelar), durante=EstadoDU.RUN)
        finally:
            self.cancelar = self._run_desde = None
            reloj.cancel()
            self.refrescar()

    async def _reloj(self) -> None:
        """Actualiza los segundos del banner de RUN mientras corre."""
        while self._run_desde is not None:
            await asyncio.sleep(1)
            if self._run_desde is not None:
                self.banner.mostrar(int(time.monotonic() - self._run_desde))
                self.banner.control.update()

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

        self._pedido = None

        def operacion() -> None:
            sesion.reset()
            sesion.dump()

        await self._ejecutar(operacion)

    async def leer_memoria(self) -> None:
        """Botón Leer: un rango de la DMEM con DUMP_MEM, que se muestra aparte (AC3)."""
        sesion = self.sesion
        if sesion is None or not self._puede_leer():
            return
        try:
            addr, n = rango_desde_hasta(
                self.memoria.desde.value or "", self.memoria.hasta.value or ""
            )
        except ValueError as error:
            self._avisar(str(error))
            return
        leido: dict[int, int] = {}
        if await self._ejecutar(lambda: leido.update(sesion.dump_mem(addr, n).como_dict())):
            self._pedido = (self._snapshot.ciclos if self._snapshot is not None else 0, leido)
            self.refrescar()

    # --- Historial: exportar, reabrir y verificar (US-505) ----------------------------------

    async def exportar_sesion(self) -> None:
        h = self._historial()
        if h is None or len(h) == 0 or self.estado.ocupado:
            return
        elegido = await self.picker.save_file(
            dialog_title="Exportar sesión",
            initial_directory=str(ASM),
            file_name="sesion.json",
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["json"],
        )
        if not elegido:
            return
        ruta = Path(elegido)
        try:
            exportar(ruta, h, self._programa(), self.fuente_cargada)
        except OSError as error:
            self._avisar(f"No se pudo exportar a {ruta.name}: {error}")
            return
        self._avisar(f"Sesión exportada en {ruta}")

    async def reabrir_sesion(self) -> None:
        """Abre una sesión exportada y se navega igual que en vivo (AC2), sin placa."""
        if self.estado.conectado or self.estado.ocupado:
            self._avisar("Desconectate para reabrir una sesión: la placa tiene su historial.")
            return
        archivos = await self.picker.pick_files(
            dialog_title="Reabrir sesión",
            initial_directory=str(ASM),
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["json"],
        )
        if not archivos or archivos[0].path is None:
            return
        ruta = Path(archivos[0].path)
        try:
            guardada = leer(ruta)
        except ErrorSesionGuardada as error:
            self._avisar(str(error))
            return
        self.abierta, self.origen = guardada.historial, ruta.name
        self.programa_abierto, self.fuente_cargada = guardada.programa, guardada.fuente
        self.cargada = self._verificacion = self._pedido = None
        if guardada.fuente is not None:
            self.panel.editor.value = guardada.fuente
            self.ruta = None  # que Guardar no pise el .asm abierto antes con este texto
            self.al_ensamblar()
            imagen = self.imagen
            if (
                imagen is not None
                and self.texto_imagen == guardada.fuente
                and imagen.palabras == guardada.programa
            ):
                self.cargada = imagen  # el listado es el de la sesión: se resalta la línea
                self.editando = False
        self.ir_a_pagina(0)

    async def verificar(self) -> None:
        """Corre el programa en el golden model y compara con el último snapshot (AC3)."""
        h = self._historial()
        programa = self._programa()
        snaps = list(h) if h is not None else []
        final = snaps[-1] if snaps else None
        resultado: Verificacion | str
        if programa is None:
            resultado = "No se sabe qué programa corrió: cargalo desde la GUI."
        elif final is None or final.motivo not in (Motivo.HALTED, Motivo.ILLEGAL):
            resultado = "El programa no terminó: corré hasta el final (F5) o dale Paso hasta HALT."
        else:
            esperado = await asyncio.to_thread(esperado_de, programa)  # hasta 100 000 instr.
            if esperado is None:
                resultado = "El programa no termina en el golden model: no hay con qué comparar."
            else:
                filas = comparacion(final, esperado)
                origenes = {}
                for d in filas:
                    if not d.ok and (o := origen_de(snaps, d.que)) is not None:
                        origenes[d.que] = (o[0], o[1], snaps[o[0]].ciclos)
                resultado = Verificacion(
                    filas,
                    final.ciclos,
                    f"{esperado.motivo.name} en 0x{esperado.pc:03x}",
                    origenes,
                )
        self._verificacion = resultado
        self.refrescar()

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
            self.con_error, self.editando = True, True
        else:
            self.imagen, self.texto_imagen, self.con_error = imagen, texto, False
            self.panel.mostrar_mensajes(None, imagen.advertencias, self.panel.ir_a_linea)
            self.panel.mostrar_listado(imagen, texto)
            self.estado = replace(self.estado, imagen_valida=True)
        self.refrescar()

    async def _ensamblar_boton(self) -> None:
        self.al_ensamblar()

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
        if archivos and archivos[0].path is not None:
            await self.abrir_ruta(Path(archivos[0].path))

    async def abrir_ruta(self, ruta: Path) -> None:
        """Pone el .asm en el editor, lo ensambla y va a la página Programa."""
        try:
            texto = ruta.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            self._avisar(f"No se pudo abrir {ruta.name}: {error}")
            return
        self.ruta = ruta
        self.panel.editor.value = texto
        self.editando = True
        self.al_ensamblar()
        self.ir_a_pagina(0)

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
        self._avisar(f"Guardado en {ruta}")
        self.refrescar()

    # --- Teclado y ventana -----------------------------------------------------------------

    async def tecla(self, e: ft.KeyboardEvent) -> None:
        """Atajos. Cada acción revisa `acciones_habilitadas`: un atajo no saltea a un botón
        deshabilitado (AC3)."""
        atajos: dict[tuple[str, bool, bool], Callable[[], Awaitable[None]]] = {
            ("F5", False, False): self.correr,
            ("F5", False, True): self.abortar,
            ("Escape", False, False): self.abortar,
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
