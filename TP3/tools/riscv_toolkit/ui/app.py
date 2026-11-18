"""GUI de escritorio del TP3 (Hito 5, ADR-012): arma la ventana y el tema.

Es la única capa que importa Flet (PRD §4.3). Base visual elegida con la maqueta: semilla
#1F7A52 con la variante tonal de Flet, modo claro, densidad compacta, menú lateral, Inter para
el texto y JetBrains Mono para el código. Las fuentes viajan en `assets/fonts/` (licencia OFL)
para que la GUI se vea igual en Linux y Windows sin depender de lo que tenga instalado la PC.
"""

from pathlib import Path

import flet as ft

ASSETS = Path(__file__).parent / "assets"
SEMILLA = "#1F7A52"
FUENTE = "Inter"
FUENTE_CODIGO = "JetBrains Mono"  # registros, latches, memoria y el editor
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


def armar(page: ft.Page) -> None:
    """Configura la página y arma el esqueleto: menú lateral y área de contenido."""
    page.title = "RISC-V TP3 - Debug Unit"
    page.theme_mode = ft.ThemeMode.LIGHT
    page.fonts = FUENTES
    page.theme = tema()
    page.padding = 0

    menu = ft.NavigationRail(
        selected_index=0,
        label_type=ft.NavigationRailLabelType.ALL,
        destinations=[
            ft.NavigationRailDestination(icon=ft.Icons.CODE, label="Programa"),
        ],
    )
    # Placeholder: el panel de programa llega en el paso 5 de US-501.
    contenido = ft.Container(ft.Text("Programa"), expand=True, padding=16)
    page.add(ft.Row([menu, ft.VerticalDivider(width=1), contenido], expand=True))


def main() -> int:
    """Abre la ventana y bloquea hasta que se cierra."""
    ft.run(armar, assets_dir=str(ASSETS))
    return 0
