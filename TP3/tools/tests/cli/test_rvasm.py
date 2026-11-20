"""CLI `rvasm`, el subcomando `asm` (US-107, AC5)."""

import subprocess
import sys
from pathlib import Path

import pytest

from riscv_toolkit.__main__ import main
from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.salidas import a_bin, a_hex, a_lst

TOOLS = Path(__file__).parents[2]

PROGRAMA = """\
addi x1, x0, 5
nop
halt
"""


@pytest.fixture
def asm(tmp_path: Path) -> Path:
    archivo = tmp_path / "programa.asm"
    archivo.write_text(PROGRAMA, encoding="utf-8")
    return archivo


# --- Formatos y archivo de salida --------------------------------------------------------------


def test_por_defecto_hex_al_lado_de_la_entrada(asm: Path) -> None:
    assert main(["asm", str(asm)]) == 0
    assert asm.with_suffix(".hex").read_text() == a_hex(ensamblar(PROGRAMA))


def test_formato_por_la_extension_de_la_salida(asm: Path, tmp_path: Path) -> None:
    salida = tmp_path / "otro.bin"
    assert main(["asm", str(asm), "-o", str(salida)]) == 0
    assert salida.read_bytes() == a_bin(ensamblar(PROGRAMA))


def test_format_manda_sobre_la_extension(asm: Path, tmp_path: Path) -> None:
    salida = tmp_path / "programa.txt"
    assert main(["asm", str(asm), "-o", str(salida), "--format", "lst"]) == 0
    assert salida.read_text(encoding="utf-8") == a_lst(ensamblar(PROGRAMA), PROGRAMA)


def test_extension_desconocida_usa_hex(asm: Path, tmp_path: Path) -> None:
    salida = tmp_path / "programa.mem"
    assert main(["asm", str(asm), "-o", str(salida)]) == 0
    assert salida.read_text() == a_hex(ensamblar(PROGRAMA))


def test_salida_por_pantalla(asm: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["asm", str(asm), "--format", "lst", "-o", "-"]) == 0
    assert capsys.readouterr().out == a_lst(ensamblar(PROGRAMA), PROGRAMA)
    assert not asm.with_suffix(".lst").exists()


def test_formato_inexistente_es_error_de_uso(asm: Path) -> None:
    with pytest.raises(SystemExit) as salida:
        main(["asm", str(asm), "--format", "elf"])
    assert salida.value.code == 2


# --- Errores y advertencias (AC5) --------------------------------------------------------------


def test_error_de_ensamblado(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    asm = tmp_path / "malo.asm"
    asm.write_text("addi x1, x0, 5\nmul x1, x2, x3\n", encoding="utf-8")
    assert main(["asm", str(asm)]) == 1
    assert f"{asm}:2: error: mnemónico desconocido 'mul'" in capsys.readouterr().err
    assert not asm.with_suffix(".hex").exists()


def test_advertencias_a_stderr(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    asm = tmp_path / "sin_halt.asm"
    asm.write_text("addi x1, x0, 5\n", encoding="utf-8")
    assert main(["asm", str(asm)]) == 0  # una advertencia no impide generar la salida
    salida = capsys.readouterr()
    assert f"{asm}: advertencia: el programa no termina en halt" in salida.err
    assert "no termina en halt" not in salida.out


def test_entrada_inexistente(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["asm", str(tmp_path / "no_existe.asm")]) == 1
    assert "no se pudo leer" in capsys.readouterr().err


def test_no_se_puede_escribir(
    asm: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    salida = tmp_path / "no_existe" / "programa.hex"
    assert main(["asm", str(asm), "-o", str(salida)]) == 1
    assert "no se pudo escribir" in capsys.readouterr().err


@pytest.mark.parametrize(("programa", "codigo"), [(PROGRAMA, 0), ("mul x1, x2, x3\n", 1)])
def test_codigo_de_salida_del_proceso(tmp_path: Path, programa: str, codigo: int) -> None:
    # De punta a punta, como lo corre un Makefile: el código tiene que llegar al sistema.
    asm = tmp_path / "programa.asm"
    asm.write_text(programa, encoding="utf-8")
    resultado = subprocess.run(  # noqa: S603 - el intérprete actual con argumentos fijos
        [sys.executable, "-m", "riscv_toolkit", "asm", str(asm)],
        cwd=TOOLS,
        capture_output=True,
        check=False,
    )
    assert resultado.returncode == codigo
