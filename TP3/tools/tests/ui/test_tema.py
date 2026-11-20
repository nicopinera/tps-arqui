"""Tema y fuentes de la GUI (US-501). La ventana en sí se prueba a mano (checklist_ui.md)."""

import flet as ft

from riscv_toolkit.ui import tema


def test_las_fuentes_registradas_existen() -> None:
    # Una ruta mal escrita no da error: Flutter cae en silencio a la fuente por defecto.
    for archivo in tema.FUENTES.values():
        assert (tema.ASSETS / archivo).is_file(), archivo


def test_tema_sale_de_la_semilla_compacto_y_con_inter() -> None:
    t = tema.tema()
    assert t.color_scheme_seed == "#1F7A52"
    assert t.visual_density is ft.VisualDensity.COMPACT
    assert t.font_family == tema.FUENTE
