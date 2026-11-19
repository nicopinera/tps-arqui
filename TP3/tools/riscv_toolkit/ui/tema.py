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
