"""Prueba mínima de que el paquete se importa sin instalarlo (US-102)."""

import tomllib
from pathlib import Path

import pytest

from riscv_toolkit.__main__ import VERSION, main


def test_main_muestra_la_version(capsys: pytest.CaptureFixture[str]) -> None:
    assert main() == 0
    assert VERSION in capsys.readouterr().out


def test_version_coincide_con_pyproject() -> None:
    pyproject = tomllib.loads((Path(__file__).parents[1] / "pyproject.toml").read_text("utf-8"))
    assert pyproject["project"]["version"] == VERSION
