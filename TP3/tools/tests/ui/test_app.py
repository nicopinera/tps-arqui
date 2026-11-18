"""Armado de la ventana (US-501, paso 1). La ventana en sí se prueba a mano."""

import flet as ft

from riscv_toolkit.ui import app


def test_las_fuentes_registradas_existen() -> None:
    # Una ruta mal escrita no da error: Flutter cae en silencio a la fuente por defecto.
    for archivo in app.FUENTES.values():
        assert (app.ASSETS / archivo).is_file(), archivo


def test_tema_sale_de_la_semilla_compacto_y_con_inter() -> None:
    tema = app.tema()
    assert tema.color_scheme_seed == "#1F7A52"
    assert tema.visual_density is ft.VisualDensity.COMPACT
    assert tema.font_family == app.FUENTE
