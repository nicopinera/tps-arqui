"""Parser del ensamblador (US-106, AC1 y AC4)."""

import pytest

from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.parser import SINTAXIS, LineaAsm, parsear
from riscv_toolkit.isa.instrucciones import INSTRUCCIONES


def _una(linea: str) -> LineaAsm:
    (resultado,) = parsear(linea)
    return resultado


def test_todas_las_instrucciones_tienen_sintaxis() -> None:
    assert set(INSTRUCCIONES) <= set(SINTAXIS)


@pytest.mark.parametrize(
    ("linea", "mnemonico", "operandos"),
    [
        ("add x3, x1, x2", "add", [3, 1, 2]),
        ("sub x31, x0, x31", "sub", [31, 0, 31]),
        ("addi x5, x5, -1", "addi", [5, 5, -1]),
        ("andi x1, x2, 0xFF", "andi", [1, 2, 255]),
        ("slli x5, x5, 2", "slli", [5, 5, 2]),
        ("lw x5, -4(x2)", "lw", [5, -4, 2]),
        ("lbu x1, 0(x0)", "lbu", [1, 0, 0]),
        ("jalr x0, 0(x1)", "jalr", [0, 0, 1]),
        ("sw x5, 8(x2)", "sw", [5, 8, 2]),
        ("beq x1, x2, fin", "beq", [1, 2, "fin"]),
        ("lui x1, 0x12345", "lui", [1, 0x12345]),
        ("jal x1, funcion", "jal", [1, "funcion"]),
        ("halt", "halt", []),
        ("nop", "nop", []),
        ("mv x5, x6", "mv", [5, 6]),
        ("j loop", "j", ["loop"]),
        ("ret", "ret", []),
        (".word 0xDEADBEEF", ".word", [0xDEADBEEF]),
        (".word -1", ".word", [-1]),
        ("addi x1, x1, -0x10", "addi", [1, 1, -16]),
        ("addi x1, x1, 010", "addi", [1, 1, 10]),
    ],
)
def test_operandos(linea: str, mnemonico: str, operandos: list[int | str]) -> None:
    resultado = _una(linea)
    assert resultado.mnemonico == mnemonico
    assert resultado.operandos == operandos
    assert resultado.etiqueta is None


def test_etiqueta_e_instruccion() -> None:
    assert _una("loop: addi x5, x5, -1") == LineaAsm("loop", "addi", [5, 5, -1], 1)


def test_etiqueta_sola() -> None:
    assert _una("fin:") == LineaAsm("fin", None, [], 1)


def test_lineas_vacias_y_comentarios_no_aparecen_pero_cuentan() -> None:
    texto = "# programa\n\n  nop\n\t\n  halt   # fin\n"
    assert parsear(texto) == [LineaAsm(None, "nop", [], 3), LineaAsm(None, "halt", [], 5)]


def test_texto_vacio() -> None:
    assert parsear("") == []


@pytest.mark.parametrize(
    ("linea", "mensaje"),
    [
        # Mnemónico
        ("li x5, 10", "mnemónico desconocido 'li'"),
        ("ADDI x5, x5, 1", "mnemónico desconocido 'ADDI'"),
        (".data", "mnemónico desconocido '.data'"),
        ("x5, x5", "mnemónico desconocido 'x5'"),
        ("a: nop:", "mnemónico desconocido 'nop'"),
        # Registros (AC1)
        ("add x32, x1, x2", r"registro inválido 'x32' \(x0\.\.x31\)"),
        ("add x05, x1, x2", "registro inválido 'x05'"),
        ("addi t0, t0, 1", "se esperaba un registro y vino 't0'"),
        ("add X5, x1, x2", "se esperaba un registro y vino 'X5'"),
        # Cantidad
        ("add x1, x2", "faltan operandos: se escribe 'add registro, registro, registro'"),
        ("add x1, x2,", "faltan operandos"),
        ("lw x5, 8(x2", r"faltan operandos: se escribe 'lw registro, offset\(registro\)'"),
        ("nop x1", "sobran operandos: se escribe 'nop'"),
        ("add x1, x2, x3, x4", "sobran operandos"),
        # Tipo y puntuación
        ("add x1 x2 x3", "se esperaba una coma y vino 'x2'"),
        ("addi x5, x5, loop", "se esperaba un inmediato y vino 'loop'"),
        ("lw x5, x2", "se esperaba un inmediato y vino 'x2'"),
        ("lw x5, (x2)", r"se esperaba un inmediato y vino '\('"),
        ("lw x5, 8 x2", r"se esperaba '\(' y vino 'x2'"),
        ("beq x1, x2, 8", "se esperaba una etiqueta y vino '8'"),
        ("jal fin", "se esperaba un registro y vino 'fin'"),
    ],
)
def test_errores(linea: str, mensaje: str) -> None:
    with pytest.raises(ErrorEnsamblado, match=f"^línea 2: {mensaje}"):
        parsear(f"nop\n{linea}")
