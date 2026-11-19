"""Página Resumen: las cuentas de la corrida (ciclos, CPI, riesgos) y tres gráficos chicos.

Las cuentas son de `ui/historial.py` (`resumen`). Los gráficos son contenedores con alto o
ancho proporcional: no hace falta una biblioteca de gráficos para barras.
"""

import flet as ft

from riscv_toolkit.ui.historial import Resumen
from riscv_toolkit.ui.tema import RIESGO, tarjeta, titulo

MAX_BARRAS = 120  # shortcut: solo los últimos 120 ciclos en "etapas ocupadas"
_ALTO_BARRAS = 100  # px para 5 etapas
_COLOR_REPARTO = {
    "Útiles": ft.Colors.PRIMARY,
    "Llenar y vaciar": ft.Colors.OUTLINE_VARIANT,
    "Stall": RIESGO["st"][0],
    "Flush": RIESGO["fl"][0],
}


def _tile(valor: ft.Text, nombre: str, sub: str) -> ft.Container:
    return tarjeta(
        ft.Text(nombre, size=12, color=ft.Colors.ON_SURFACE_VARIANT),
        valor,
        ft.Text(sub, size=11, color=ft.Colors.ON_SURFACE_VARIANT),
        expand=True,
    )


class VistaResumen:
    def __init__(self) -> None:
        self._valores = {
            n: ft.Text(size=24, weight=ft.FontWeight.W_600)
            for n in ("ciclos", "instr", "cpi", "stalls", "flushes", "fwd")
        }
        v = self._valores
        self._aviso = ft.Text(size=12, color=RIESGO["st"][0])
        self._barras = ft.Row(
            spacing=1, height=_ALTO_BARRAS + 14, vertical_alignment=ft.CrossAxisAlignment.END
        )
        self._reparto = ft.Row(spacing=0, height=26)
        self._leyenda = ft.Row(spacing=12, wrap=True)
        self._mezcla = ft.Column(spacing=4)
        self.control = ft.Column(
            [
                titulo("Resumen de la corrida"),
                self._aviso,
                ft.Row(
                    [
                        _tile(v["ciclos"], "Ciclos", "del contador de la DU"),
                        _tile(v["instr"], "Instrucciones", "terminadas (pasaron por WB)"),
                        _tile(v["cpi"], "CPI", "ciclos / instrucción; ideal → 1"),
                        _tile(v["stalls"], "Stalls", "load-use: una burbuja cada uno"),
                        _tile(v["flushes"], "Flushes", "instrucciones descartadas"),
                        _tile(v["fwd"], "Forwardings", "operandos adelantados"),
                    ]
                ),
                tarjeta(
                    titulo("Etapas ocupadas por ciclo"),
                    ft.Text(
                        "Alto = cuántas de las 5 etapas tienen una instrucción. Arriba, el "
                        "color del riesgo del ciclo.",
                        size=12,
                        color=ft.Colors.ON_SURFACE_VARIANT,
                    ),
                    self._barras,
                ),
                ft.Row(
                    [
                        tarjeta(
                            titulo("En qué se fueron los ciclos"),
                            self._reparto,
                            self._leyenda,
                            expand=True,
                        ),
                        tarjeta(titulo("Mezcla de instrucciones"), self._mezcla, expand=True),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.START,
                ),
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=12,
        )

    def mostrar(self, r: Resumen | None) -> None:
        if r is None or not r.ocupadas:
            for valor in self._valores.values():
                valor.value = "—"
            self._aviso.value = "Sin historial: cargá un programa y avanzá con Paso."
            self._barras.controls = self._reparto.controls = []
            self._leyenda.controls = self._mezcla.controls = []
            return
        v = self._valores
        v["ciclos"].value, v["instr"].value = str(r.ciclos), str(r.instrucciones)
        v["cpi"].value = f"{r.cpi:.2f}" if r.cpi is not None else "—"
        v["stalls"].value, v["flushes"].value = str(r.stalls), str(r.flushes)
        v["fwd"].value = str(r.forwardings)
        self._aviso.value = (
            ""
            if r.completo
            else "Hubo un RUN: de esos ciclos llega solo el estado final, así "
            "que las cuentas de riesgos y etapas son solo de lo que se hizo paso a paso."
        )
        ocupadas = r.ocupadas[-MAX_BARRAS:]
        eventos = r.eventos[-MAX_BARRAS:]
        barras: list[ft.Control] = []
        for i, (n, ev) in enumerate(zip(ocupadas, eventos, strict=True)):
            ultima = i == len(ocupadas) - 1
            barras.append(
                ft.Column(
                    [
                        ft.Container(
                            width=6,
                            height=6,
                            border_radius=3,
                            bgcolor=RIESGO[ev[0]][0] if ev else None,
                        ),
                        ft.Container(
                            height=max(1, n * _ALTO_BARRAS // 5),
                            expand=False,
                            bgcolor=ft.Colors.TERTIARY if ultima else ft.Colors.PRIMARY_CONTAINER,
                            tooltip=f"{n} etapas",
                        ),
                    ],
                    spacing=2,
                    expand=1,
                    alignment=ft.MainAxisAlignment.END,
                    horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                )
            )
        self._barras.controls = barras
        total = sum(r.reparto.values()) or 1
        self._reparto.controls = [
            ft.Container(expand=n, bgcolor=_COLOR_REPARTO[k], tooltip=f"{k}: {n}")
            for k, n in r.reparto.items()
            if n
        ]
        self._leyenda.controls = [
            ft.Row(
                [
                    ft.Container(width=10, height=10, bgcolor=_COLOR_REPARTO[k], border_radius=2),
                    ft.Text(f"{k}: {n} ({100 * n // total} %)", size=12),
                ],
                spacing=4,
                tight=True,
            )
            for k, n in r.reparto.items()
        ]
        maximo = max(r.mezcla.values(), default=1)
        self._mezcla.controls = [
            ft.Row(
                [
                    ft.Text(clase, size=12, width=150),
                    ft.Container(
                        width=max(2, 220 * n // maximo),
                        height=14,
                        bgcolor=RIESGO["ht"][0] if clase == "HALT" else ft.Colors.PRIMARY,
                        border_radius=2,
                    ),
                    ft.Text(str(n), size=12),
                ],
            )
            for clase, n in r.mezcla.items()
        ]
