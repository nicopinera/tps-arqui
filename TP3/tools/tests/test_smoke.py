"""Prueba mínima de que el paquete se instala y se importa (US-102)."""

from importlib.metadata import version

import pytest

from riscv_toolkit.__main__ import main


def test_main_muestra_la_version(capsys: pytest.CaptureFixture[str]) -> None:
    assert main() == 0
    assert version("riscv-toolkit") in capsys.readouterr().out
