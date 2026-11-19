"""Detalle de un latch (US-502, AC4): todos sus campos con nombre, en hex y en decimal."""

from collections.abc import Callable

import flet as ft

from riscv_toolkit.disasm.disassembler import desensamblar
from riscv_toolkit.protocol.snapshot import LatchIDEX, LatchIFID, Snapshot
from riscv_toolkit.ui.pipeline import LATCHES, campos_latch, latches
from riscv_toolkit.ui.tema import FUENTE_CODIGO


class DetalleLatch:
    """Selector del latch y una tabla campo / hex / decimal.

    Hay una tabla por latch, armada una sola vez (la cantidad de campos no cambia); al
    refrescar solo se cambian los textos y se muestra la del latch elegido.
    """

    def __init__(self, al_cambiar: Callable[[], None]) -> None:
        """`al_cambiar`: se llama cuando el usuario elige otro latch (la vista lo marca)."""
        self.selector = ft.SegmentedButton(
            segments=[ft.Segment(n, label=n) for n in LATCHES],
            selected=[LATCHES[0]],
            on_change=lambda _: al_cambiar(),
        )
        self._instr = ft.Text(font_family=FUENTE_CODIGO, size=13)
        self._celdas: dict[str, list[tuple[ft.Text, ft.Text]]] = {}
        self._tablas: dict[str, ft.DataTable] = {}
        self._instr_de: dict[str, str] = {}  # latch → su instrucción desensamblada
        vacio = latches(None)
        for nombre in LATCHES:
            filas = []
            celdas = []
            for campo, _, _ in campos_latch(vacio[nombre]):
                hexa = ft.Text(font_family=FUENTE_CODIGO, size=13)
                dec = ft.Text(font_family=FUENTE_CODIGO, size=13)
                celdas.append((hexa, dec))
                filas.append(
                    ft.DataRow(
                        [
                            ft.DataCell(ft.Text(campo, font_family=FUENTE_CODIGO, size=13)),
                            ft.DataCell(hexa),
                            ft.DataCell(dec),
                        ]
                    )
                )
            self._celdas[nombre] = celdas
            self._tablas[nombre] = ft.DataTable(
                columns=[ft.DataColumn(label=t) for t in ("Campo", "Hex", "Decimal")],
                rows=filas,
                heading_row_color=ft.Colors.SURFACE_CONTAINER_HIGHEST,  # encabezado con fondo
                data_row_min_height=26,
                data_row_max_height=26,
                heading_row_height=32,
                column_spacing=32,
                visible=nombre == LATCHES[0],
            )
        self.control = ft.Column(
            [
                ft.Row([ft.Text("Latch", weight=ft.FontWeight.W_600), self.selector, self._instr]),
                *self._tablas.values(),
            ],
            spacing=8,
        )

    def elegir(self, nombre: str) -> None:
        self.selector.selected = [nombre]
        self._mostrar_elegida()

    def elegido(self) -> str:
        return self.selector.selected[0] if self.selector.selected else LATCHES[0]

    def _mostrar_elegida(self) -> None:
        for nombre, tabla in self._tablas.items():
            tabla.visible = nombre == self.elegido()
        self._instr.value = self._instr_de.get(self.elegido(), "")

    def mostrar(self, snapshot: Snapshot | None) -> None:
        todos = latches(snapshot)
        self._instr_de = {}
        for nombre, latch in todos.items():
            for (hexa, dec), (_, h, d) in zip(
                self._celdas[nombre], campos_latch(latch), strict=True
            ):
                hexa.value, dec.value = h, d
            # Con PC, como en la tarjeta: el destino de un branch sale absoluto (0x10, no .+8).
            pc = latch.pc if isinstance(latch, LatchIFID | LatchIDEX) else latch.pc_plus4 - 4
            texto = desensamblar(latch.instr, pc) if latch.valid else "burbuja"
            self._instr_de[nombre] = f"instr: {texto}" if snapshot is not None else ""
        self._mostrar_elegida()
