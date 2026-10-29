"""Mismas palabras que GNU as para las 32 instrucciones estándar (US-106, AC2, ADR-013).

El .hex de referencia se generó una vez con `make gnu-ref` y está versionado: este test no
necesita GNU instalado.
"""

from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.parser import parsear
from riscv_toolkit.isa.instrucciones import HALT_WORD, INSTRUCCIONES

FIXTURES = Path(__file__).parent / "fixtures"
ASM = FIXTURES / "todas_las_instrucciones.asm"
HEX = FIXTURES / "todas_las_instrucciones.hex"


def test_igual_que_gnu() -> None:
    assert HEX.exists(), f"falta {HEX.name}: generalo con `make gnu-ref` desde TP3/"
    referencia = [int(linea, 16) for linea in HEX.read_text().split()]
    imagen = ensamblar(ASM.read_text(encoding="utf-8"))
    # GNU no conoce halt: el nuestro es el único agregado, al final.
    assert imagen.palabras[-1] == HALT_WORD
    assert imagen.palabras[:-1] == referencia


def test_el_fixture_usa_las_32_estandar() -> None:
    usadas = {linea.mnemonico for linea in parsear(ASM.read_text(encoding="utf-8"))}
    assert usadas - {None} == set(INSTRUCCIONES) - {"halt"}
