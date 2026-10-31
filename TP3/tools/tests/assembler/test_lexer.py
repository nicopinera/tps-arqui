"""Lexer del ensamblador (US-106)."""

import pytest

from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.lexer import TipoToken, Token, tokenizar

ETIQUETA = TipoToken.ETIQUETA
DIRECTIVA = TipoToken.DIRECTIVA
REGISTRO = TipoToken.REGISTRO
INMEDIATO = TipoToken.INMEDIATO
IDENT = TipoToken.IDENTIFICADOR
COMA = TipoToken.COMA
ABRE = TipoToken.PAR_ABRE
CIERRA = TipoToken.PAR_CIERRA


def _pares(linea: str) -> list[tuple[TipoToken, str]]:
    return [(t.tipo, t.texto) for t in tokenizar(linea, 1)]


def test_devuelve_tokens() -> None:
    assert tokenizar("nop", 1) == [Token(IDENT, "nop")]


def test_linea_completa() -> None:
    assert _pares("loop:  addi x5, x5, -1   # decrementa") == [
        (ETIQUETA, "loop"),
        (IDENT, "addi"),
        (REGISTRO, "x5"),
        (COMA, ","),
        (REGISTRO, "x5"),
        (COMA, ","),
        (INMEDIATO, "-1"),
    ]


def test_offset_con_base() -> None:
    assert _pares("lw x5, -4(x2)") == [
        (IDENT, "lw"),
        (REGISTRO, "x5"),
        (COMA, ","),
        (INMEDIATO, "-4"),
        (ABRE, "("),
        (REGISTRO, "x2"),
        (CIERRA, ")"),
    ]


def test_branch_con_etiqueta() -> None:
    assert _pares("bne x5, x0, loop") == [
        (IDENT, "bne"),
        (REGISTRO, "x5"),
        (COMA, ","),
        (REGISTRO, "x0"),
        (COMA, ","),
        (IDENT, "loop"),
    ]


def test_directiva() -> None:
    assert _pares(".word 0xDEADBEEF") == [(DIRECTIVA, ".word"), (INMEDIATO, "0xDEADBEEF")]


def test_etiqueta_sola_y_tabs() -> None:
    assert _pares("\tfin_2:\t") == [(ETIQUETA, "fin_2")]


@pytest.mark.parametrize("linea", ["", "   ", "# solo comentario", "\t# con tab"])
def test_lineas_sin_tokens(linea: str) -> None:
    assert tokenizar(linea, 1) == []


@pytest.mark.parametrize("texto", ["0", "7", "2047", "-2048", "0x1F", "0xfff", "-0x10"])
def test_inmediatos(texto: str) -> None:
    assert _pares(texto) == [(INMEDIATO, texto)]


@pytest.mark.parametrize("texto", ["xori", "x5a", "x_1", "xor"])
def test_empieza_con_x_pero_no_es_registro(texto: str) -> None:
    assert _pares(texto) == [(IDENT, texto)]


@pytest.mark.parametrize("texto", ["x0", "x31", "x32", "x99"])
def test_registros_aunque_no_existan(texto: str) -> None:
    # x32 es un REGISTRO para el lexer; lo rechaza el parser con un mensaje claro.
    assert _pares(texto) == [(REGISTRO, texto)]


def test_mayusculas_son_identificadores() -> None:
    # El parser los rechaza: no existe el mnemónico `ADDI` ni el registro `X5`.
    assert _pares("ADDI X5") == [(IDENT, "ADDI"), (IDENT, "X5")]


@pytest.mark.parametrize(
    ("linea", "caracter"),
    [
        ("addi x5, x5, @", "@"),
        ("addi x5; x5", ";"),
        ("loop : nop", ":"),
        ("addi x5, x5, - 1", "-"),
        ("addi x5, x5, 12abc", "1"),
        ("addi x5, x5, 0xZZ", "0"),
    ],
)
def test_caracter_inesperado(linea: str, caracter: str) -> None:
    with pytest.raises(ErrorEnsamblado, match=f"línea 3: carácter inesperado '{caracter}'"):
        tokenizar(linea, 3)
