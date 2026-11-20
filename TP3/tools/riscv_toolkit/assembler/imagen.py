"""Resultado del ensamblador: el programa en código máquina y su relación con la fuente (US-106)."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Imagen:
    """Programa ensamblado. Las direcciones son en bytes, como el PC (0, 4, 8, …)."""

    palabras: list[int]  # una palabra de 32 bits por instrucción, en orden de dirección
    simbolos: dict[str, int]  # etiqueta → dirección
    mapa_lineas: dict[int, int]  # dirección → línea de la fuente (la GUI resalta esa línea)
    expansiones: dict[int, str]  # dirección → instrucción real de cada pseudo (`addi x0, x0, 0`)
    advertencias: list[str]  # HALT agregado, accesos desalineados, …
