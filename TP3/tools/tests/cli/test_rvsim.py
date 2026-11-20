"""CLI `rvsim`, el subcomando `sim` (US-108)."""

from pathlib import Path

import pytest

from riscv_toolkit.__main__ import main
from riscv_toolkit.iss.expected import leer_expected
from riscv_toolkit.iss.golden_model import Motivo


def _asm(tmp_path: Path, texto: str) -> Path:
    archivo = tmp_path / "programa.asm"
    archivo.write_text(texto, encoding="utf-8")
    return archivo


def test_resumen(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["sim", str(_asm(tmp_path, "addi x5, x0, 7\nhalt"))]) == 0
    assert "HALTED en 0x004, 1 instrucciones" in capsys.readouterr().out


def test_dump(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    asm = _asm(tmp_path, "addi x5, x0, 7\nsw x5, 0x10(x0)\nhalt")
    assert main(["sim", str(asm), "--dump"]) == 0
    salida = capsys.readouterr().out
    assert "x5  = 0x00000007" in salida
    assert "memoria usada (1 palabras):" in salida
    assert "0x010: 0x00000007" in salida


def test_expect(tmp_path: Path) -> None:
    salida = tmp_path / "programa.expected"
    asm = _asm(tmp_path, "addi x5, x0, 7\nsw x5, 0x10(x0)\nhalt")
    assert main(["sim", str(asm), "--expect", str(salida)]) == 0
    estado = leer_expected(salida.read_text("utf-8"))
    assert estado.regs[5] == 7
    assert estado.mem_usada == {0x10: 7}
    assert estado.motivo is Motivo.HALTED


def test_ilegal_es_un_resultado_valido(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["sim", str(_asm(tmp_path, ".word 0"))]) == 0
    assert "ILLEGAL en 0x000" in capsys.readouterr().out


def test_timeout_sale_con_1_y_no_escribe(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    salida = tmp_path / "programa.expected"
    asm = _asm(tmp_path, "loop: jal x0, loop")
    assert main(["sim", str(asm), "--max-instr", "20", "--expect", str(salida)]) == 1
    assert "TIMEOUT" in capsys.readouterr().err
    assert not salida.exists()


def test_advertencias_a_stderr(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    asm = _asm(tmp_path, "addi x1, x0, 3\nlw x5, 0(x1)\nhalt")
    assert main(["sim", str(asm)]) == 0
    assert "lw desalineado" in capsys.readouterr().err


def test_error_de_ensamblado(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["sim", str(_asm(tmp_path, "addi x1, x0\n"))]) == 1
    assert "programa.asm:1: error:" in capsys.readouterr().err


def test_archivo_inexistente(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["sim", str(tmp_path / "no_existe.asm")]) == 1
    assert "no se pudo leer" in capsys.readouterr().err


def test_expect_en_carpeta_inexistente(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    asm = _asm(tmp_path, "halt")
    assert main(["sim", str(asm), "--expect", str(tmp_path / "no" / "x.expected")]) == 1
    assert "no se pudo escribir" in capsys.readouterr().err
