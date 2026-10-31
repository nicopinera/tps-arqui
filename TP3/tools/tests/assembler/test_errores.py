"""El mensaje de `ErrorEnsamblado` lleva el número de línea (US-106, AC4)."""

import pytest

from riscv_toolkit.assembler.errores import ErrorEnsamblado


def test_mensaje_con_numero_de_linea() -> None:
    error = ErrorEnsamblado(7, "registro inválido 'x32'")
    assert str(error) == "línea 7: registro inválido 'x32'"
    assert error.linea == 7
    assert error.mensaje == "registro inválido 'x32'"


def test_es_un_value_error() -> None:
    # Quien solo quiera saber si la entrada es inválida puede atrapar ValueError.
    with pytest.raises(ValueError, match="línea 1"):
        raise ErrorEnsamblado(1, "mnemónico desconocido 'li'")
