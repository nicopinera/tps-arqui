"""Formatos de salida del ensamblador: .hex, .bin y .lst (US-107, AC3 y AC4)."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.salidas import a_bin, a_hex, a_lst

TP3 = Path(__file__).parents[3]
EJEMPLO_HEX = TP3 / "hw" / "tb" / "common" / "ejemplo.hex"

# El programa de hw/tb/common/ejemplo.hex, el que verifica tb_readmemh.
EJEMPLO = """\
addi x1, x0, 5
addi x2, x0, 10
add  x3, x1, x2
halt
"""


# --- .hex (AC3) --------------------------------------------------------------------------------


def test_hex_igual_al_ejemplo_del_testbench() -> None:
    assert a_hex(ensamblar(EJEMPLO)) == EJEMPLO_HEX.read_text()


@pytest.mark.skipif(shutil.which("iverilog") is None, reason="hace falta Icarus Verilog")
def test_hex_se_carga_con_readmemh(tmp_path: Path) -> None:
    programa = tmp_path / "ejemplo.hex"
    programa.write_text(a_hex(ensamblar(EJEMPLO)))
    resultado = subprocess.run(
        ["bash", "hw/scripts/sim.sh", "tb_readmemh"],  # noqa: S607 - comando fijo del repo
        cwd=TP3,
        env={**os.environ, "HEX": str(programa), "QUIET": "1"},
        capture_output=True,
        text=True,
        check=False,
    )
    assert resultado.returncode == 0, resultado.stdout + resultado.stderr


# --- .bin (AC3) --------------------------------------------------------------------------------


def test_bin_tiene_4n_bytes_en_little_endian() -> None:
    imagen = ensamblar(EJEMPLO)
    binario = a_bin(imagen)
    assert len(binario) == 4 * len(imagen.palabras)
    assert binario[:4] == bytes([0x93, 0x00, 0x50, 0x00])  # addi x1, x0, 5 = 0x00500093
    assert binario[-4:] == bytes([0x0B, 0x00, 0x00, 0x00])  # halt


# --- .lst (AC4) --------------------------------------------------------------------------------


PROGRAMA = """\
# programa de prueba
inicio:
        addi x1, x0, 5      # x1 = 5
loop:   nop
        mv x2, x1
        bne x1, x2, loop
        j fin
        ret
fin:
"""

LISTADO = """\
# dir  palabra   línea  fuente
                        inicio:
0x000  00500093      3  addi x1, x0, 5
                        loop:
0x004  00000013      4  nop                     # addi x0, x0, 0
0x008  00008113      5  mv x2, x1               # addi x2, x1, 0
0x00c  fe209ce3      6  bne x1, x2, loop
0x010  0080006f      7  j fin                   # jal x0, fin
0x014  00008067      8  ret                     # jalr x0, 0(x1)
                        fin:
0x018  0000000b      -  halt                    # agregado por el ensamblador
"""


def test_lst_completo() -> None:
    # Etiquetas en su renglón, fuente sin comentarios y expansión de las cuatro pseudo.
    assert a_lst(ensamblar(PROGRAMA), PROGRAMA) == LISTADO


def test_lst_etiqueta_despues_del_ultimo_halt() -> None:
    texto = "halt\nfin:\n"
    assert a_lst(ensamblar(texto), texto).splitlines()[-1].strip() == "fin:"
