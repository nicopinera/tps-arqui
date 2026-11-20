"""Base visual de la GUI (Hito 5), elegida con la maqueta.

Semilla #1F7A52 con la variante tonal de Flet, modo claro, densidad compacta, Inter para el
texto y JetBrains Mono para el código. Las fuentes viajan en `assets/fonts/` (licencia OFL)
para que la GUI se vea igual en Linux y Windows sin depender de lo que tenga instalado la PC.
Los colores se piden por rol (`ft.Colors.PRIMARY_CONTAINER`, …), nunca en hex: salen todos de
la semilla.
"""

from pathlib import Path

import flet as ft

ASSETS = Path(__file__).parent / "assets"
SEMILLA = "#1F7A52"
FUENTE = "Inter"
FUENTE_CODIGO = "JetBrains Mono"  # registros, latches, memoria, el editor y el listado
# Tamaños de letra de las vistas, pensados para 1366x768 (la resolución de la maqueta).
LETRA_TABLA = 15  # celdas: latches, registros, memoria, historial, campos
LETRA_NOTA = 13  # textos secundarios: de dónde sale, quién escribió, leyendas
LETRA_INSTR = 18  # la instrucción de cada tarjeta de etapa
# Nombre de la familia → archivo, relativo a ASSETS. shortcut: solo el peso Regular (el
# negrito lo sintetiza Flutter); si se nota feo, sumar Inter-SemiBold como otra familia.
FUENTES = {
    FUENTE: "fonts/Inter-Regular.ttf",
    FUENTE_CODIGO: "fonts/JetBrainsMono-Regular.ttf",
}


def tema() -> ft.Theme:
    """El tema Material 3 de toda la GUI: la paleta sale entera de la semilla."""
    return ft.Theme(
        color_scheme_seed=SEMILLA,
        font_family=FUENTE,
        visual_density=ft.VisualDensity.COMPACT,
        use_material3=True,
    )


# --- Marcas de riesgo ----------------------------------------------------------------------
# Las únicas en hex: tienen que distinguirse entre sí y del verde de la semilla, y con roles
# (todos verdosos) no alcanzan. Valores de la maqueta para modo claro. Clave → (texto, relleno).
RIESGO = {
    "st": ("#8A5300", "#FFE5BD"),  # stall: ámbar
    "fl": ("#B3261E", "#FFDAD6"),  # flush: rojo
    "fa": ("#1259B8", "#D8E6FF"),  # forwarding A: azul
    "fb": ("#00695C", "#C8EEE7"),  # forwarding B: verde azulado
    "ht": ("#6A3FB0", "#EBDDFF"),  # HALT / terminó: violeta
    "ok": ("#1B6B3A", "#CDEFD6"),  # coincide (Verificar)
}
NOMBRE_RIESGO = {
    "st": "stall",
    "fl": "flush",
    "fa": "forwarding A",
    "fb": "forwarding B",
    "ht": "HALT",
}
PELIGRO = ("#FFFFFF", "#B3261E")  # Abortar: texto, fondo


def chip(texto: str, clave: str | None = None, *, punteado: bool = False) -> ft.Container:
    """Etiqueta chica. `clave`: un color de `RIESGO` (None: neutro). `punteado`: inactiva."""
    color, fondo = RIESGO[clave] if clave else (ft.Colors.ON_SURFACE_VARIANT, None)
    return ft.Container(
        ft.Text(texto, size=11, weight=ft.FontWeight.W_600, font_family=FUENTE_CODIGO, color=color),
        bgcolor=None if punteado else fondo or ft.Colors.SURFACE_CONTAINER_HIGHEST,
        border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT) if punteado else None,
        border_radius=4,
        padding=ft.Padding.symmetric(horizontal=6, vertical=1),
    )


def rayado() -> ft.LinearGradient:
    """Fondo a rayas diagonales de una burbuja (Flet no tiene patrones: un gradiente que se
    repite con cortes duros)."""
    claro, oscuro = ft.Colors.SURFACE_CONTAINER_LOW, ft.Colors.SURFACE_CONTAINER_HIGHEST
    return ft.LinearGradient(
        begin=ft.Alignment(-1, -1),
        end=ft.Alignment(-0.92, -0.86),
        colors=[claro, claro, oscuro, oscuro],
        stops=[0, 0.5, 0.5, 1],
        tile_mode=ft.GradientTileMode.REPEATED,
    )


def titulo(texto: str) -> ft.Text:
    return ft.Text(texto, weight=ft.FontWeight.W_600, size=15)


def tarjeta(*controles: ft.Control, expand: bool | int = False) -> ft.Container:
    """Una tarjeta con borde, como las de la maqueta."""
    return ft.Container(
        ft.Column(list(controles), spacing=8, tight=True),
        padding=12,
        border=ft.Border.all(1, ft.Colors.OUTLINE_VARIANT),
        border_radius=10,
        expand=expand,
    )
