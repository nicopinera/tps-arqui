"""Golden model (US-108): un test por instrucción con valores borde y los casos de terminación."""

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.isa.instrucciones import HALT_WORD
from riscv_toolkit.iss.golden_model import GoldenModel, Motivo
from riscv_toolkit.protocol.comandos import DMEM_DEPTH, IMEM_DEPTH

_NOP = 0x00000013  # addi x0, x0, 0


def _correr(asm: str) -> GoldenModel:
    """Ensambla `asm` y lo ejecuta hasta que termine (el ensamblador agrega el halt)."""
    modelo = GoldenModel(ensamblar(asm).palabras)
    for _ in range(1000):
        if modelo.step() is not None:
            return modelo
    raise AssertionError("el programa no terminó en 1000 instrucciones")


# --- T1: estado inicial, relleno con HALT, ilegales ----------------------------------------


def test_estado_inicial_en_cero() -> None:
    modelo = GoldenModel([])
    assert modelo.pc == 0
    assert modelo.regs == [0] * 32
    assert modelo.dmem == bytearray(DMEM_DEPTH * 4)
    assert modelo.mem_escrita == set()
    assert modelo.instrucciones_retiradas == 0
    assert modelo.advertencias == []
    assert modelo.motivo is None


def test_imem_se_rellena_con_halt() -> None:
    modelo = GoldenModel([_NOP, _NOP])
    assert len(modelo.imem) == IMEM_DEPTH
    assert modelo.imem[:2] == [_NOP, _NOP]
    assert all(palabra == HALT_WORD for palabra in modelo.imem[2:])


def test_no_modifica_la_lista_recibida() -> None:
    programa = [_NOP]
    GoldenModel(programa)
    assert programa == [_NOP]


def test_imem_vacia_ejecuta_halt() -> None:
    modelo = GoldenModel([])
    assert modelo.step() is Motivo.HALTED
    assert modelo.motivo is Motivo.HALTED


def test_programa_que_llena_la_imem_entra() -> None:
    assert len(GoldenModel([_NOP] * IMEM_DEPTH).imem) == IMEM_DEPTH


def test_programa_demasiado_largo() -> None:
    with pytest.raises(ValueError, match="palabras"):
        GoldenModel([_NOP] * (IMEM_DEPTH + 1))


@pytest.mark.parametrize("palabra", [-1, 0x1_0000_0000])
def test_palabra_fuera_de_32_bits(palabra: int) -> None:
    with pytest.raises(ValueError, match="32 bits"):
        GoldenModel([palabra])


def test_ilegal_no_avanza_ni_cuenta() -> None:
    modelo = GoldenModel([_NOP, 0x00000000])
    assert modelo.step() is None
    assert modelo.step() is Motivo.ILLEGAL
    assert modelo.pc == 4  # el PC de la ilegal (AC2)
    assert modelo.instrucciones_retiradas == 1
    assert modelo.motivo is Motivo.ILLEGAL


def test_fetch_da_la_vuelta_en_la_imem() -> None:
    modelo = GoldenModel([_NOP] * 4, imem_words_max=4)
    for _ in range(4):
        assert modelo.step() is None
    assert modelo.pc == 16  # pasó el final: la próxima palabra es la 0 otra vez
    assert modelo.step() is None


# --- T2: ALU (R e I aritméticas) ------------------------------------------------------------

# Valores de carga reutilizados: x1 = -1, x1 = 0x80000000 y x1 = 0x7FFFFFFF.
_MENOS_UNO = "addi x1, x0, -1"
_MIN_INT = "addi x1, x0, 1\nslli x1, x1, 31"
_MAX_INT = f"{_MIN_INT}\naddi x1, x1, -1"


@pytest.mark.parametrize(
    ("programa", "esperado"),
    [
        # R
        (f"{_MENOS_UNO}\naddi x2, x0, 1\nadd x3, x1, x2", 0),  # 0xFFFFFFFF + 1 da la vuelta
        (f"{_MAX_INT}\naddi x2, x0, 1\nadd x3, x1, x2", 0x80000000),  # overflow con signo
        ("addi x2, x0, 1\nsub x3, x0, x2", 0xFFFFFFFF),  # 0 - 1 sin quedar negativo
        ("addi x1, x0, 1\naddi x2, x0, 33\nsll x3, x1, x2", 2),  # solo cuentan 5 bits: 33 → 1
        (f"{_MENOS_UNO}\naddi x2, x0, 1\nslt x3, x1, x2", 1),  # -1 < 1
        (f"{_MENOS_UNO}\naddi x2, x0, 1\nsltu x3, x1, x2", 0),  # 0xFFFFFFFF no es < 1
        ("addi x1, x0, 12\naddi x2, x0, 10\nxor x3, x1, x2", 6),
        ("addi x1, x0, 12\naddi x2, x0, 10\nor x3, x1, x2", 14),
        ("addi x1, x0, 12\naddi x2, x0, 10\nand x3, x1, x2", 8),
        (f"{_MIN_INT}\naddi x2, x0, 4\nsrl x3, x1, x2", 0x08000000),  # rellena con ceros
        (f"{_MIN_INT}\naddi x2, x0, 4\nsra x3, x1, x2", 0xF8000000),  # rellena con el signo
        # I
        ("addi x3, x0, -1", 0xFFFFFFFF),  # el imm negativo se guarda sin signo
        ("addi x3, x0, -2048", 0xFFFFF800),  # el imm más chico
        (f"{_MENOS_UNO}\nslti x3, x1, 0", 1),  # -1 < 0
        ("sltiu x3, x0, -1", 1),  # 0 < 0xFFFFFFFF
        ("xori x3, x0, -1", 0xFFFFFFFF),  # xori con -1 es el NOT
        ("ori x3, x0, 5", 5),
        (f"{_MENOS_UNO}\nandi x3, x1, 15", 15),
        ("addi x1, x0, 1\nslli x3, x1, 31", 0x80000000),
        (f"{_MIN_INT}\nsrli x3, x1, 4", 0x08000000),
        (f"{_MIN_INT}\nsrai x3, x1, 4", 0xF8000000),  # imm = 0x404: el funct7 no corre de más
    ],
)
def test_alu(programa: str, esperado: int) -> None:
    assert _correr(programa).regs[3] == esperado


def test_escribir_x0_no_cambia_nada() -> None:
    modelo = _correr("addi x0, x0, 5\nadd x0, x0, x0")
    assert modelo.regs[0] == 0


def test_cada_instruccion_avanza_el_pc_y_cuenta() -> None:
    modelo = _correr("addi x1, x0, 1\naddi x2, x0, 2")
    assert modelo.pc == 8  # quedó en el halt
    assert modelo.instrucciones_retiradas == 2


# --- T3: loads y stores ---------------------------------------------------------------------

# x1 = 0x10 (base) y x2 = 0x12345680 guardado en 0x10: en memoria quedan 80 56 34 12.
_GUARDAR = "addi x1, x0, 0x10\naddi x2, x0, 0x123\nslli x2, x2, 20\naddi x3, x0, 0x456\n"
_GUARDAR += "slli x3, x3, 8\nor x2, x2, x3\nori x2, x2, 0x80\nsw x2, 0(x1)\n"


def test_sw_guarda_en_little_endian() -> None:
    modelo = _correr(_GUARDAR)
    assert modelo.regs[2] == 0x12345680
    assert modelo.dmem[0x10:0x14] == bytes([0x80, 0x56, 0x34, 0x12])


@pytest.mark.parametrize(
    ("load", "esperado"),
    [
        ("lw x5, 0(x1)", 0x12345680),
        ("lb x5, 0(x1)", 0xFFFFFF80),  # 0x80 con signo: -128
        ("lbu x5, 0(x1)", 0x00000080),  # 0x80 sin signo: 128
        ("lb x5, 1(x1)", 0x00000056),
        ("lbu x5, 3(x1)", 0x00000012),
        ("lh x5, 0(x1)", 0x00005680),
        ("lh x5, 2(x1)", 0x00001234),
        ("lhu x5, 0(x1)", 0x00005680),
    ],
)
def test_loads(load: str, esperado: int) -> None:
    assert _correr(_GUARDAR + load).regs[5] == esperado


def test_lh_extiende_el_signo() -> None:
    modelo = _correr("addi x1, x0, -1\nsh x1, 0(x0)\nlh x5, 0(x0)\nlhu x6, 0(x0)")
    assert modelo.regs[5] == 0xFFFFFFFF
    assert modelo.regs[6] == 0x0000FFFF


def test_sb_y_sh_no_pisan_los_bytes_vecinos() -> None:
    modelo = _correr(_GUARDAR + "addi x5, x0, -1\nsb x5, 1(x1)\nsh x0, 2(x1)")
    assert modelo.dmem[0x10:0x14] == bytes([0x80, 0xFF, 0x00, 0x00])


def test_lw_desalineado_lee_la_palabra_alineada() -> None:
    modelo = _correr(_GUARDAR + "lw x5, 0(x1)\nlw x6, 3(x1)")
    assert modelo.regs[6] == modelo.regs[5]  # AC5
    assert len(modelo.advertencias) == 1
    assert "lw desalineado en 0x013, se accede a 0x010" in modelo.advertencias[0]


def test_sh_desalineado_ignora_el_bit_0() -> None:
    modelo = _correr("addi x5, x0, -1\nsh x5, 3(x0)")
    assert modelo.dmem[0:4] == bytes([0x00, 0x00, 0xFF, 0xFF])
    assert len(modelo.advertencias) == 1


def test_accesos_de_un_byte_nunca_estan_desalineados() -> None:
    assert _correr("sb x0, 3(x0)\nlbu x5, 1(x0)").advertencias == []


def test_mem_escrita_marca_la_palabra_alineada() -> None:
    modelo = _correr("sb x0, 0x13(x0)\nsw x0, 0x10(x0)\nsh x0, 0x22(x0)")
    assert modelo.mem_escrita == {0x10, 0x20}  # AC3: dos stores a la misma palabra cuentan una


def test_load_no_marca_mem_escrita() -> None:
    assert _correr("lw x5, 0(x0)").mem_escrita == set()


def test_direccion_da_la_vuelta() -> None:
    # 0x410 es 0x010 en una DMEM de 1 KiB; 0 - 4 es 0x3FC
    modelo = _correr("addi x1, x0, 0x410\naddi x2, x0, 7\nsw x2, 0(x1)\nsw x2, -4(x0)")
    assert modelo.dmem[0x10] == 7
    assert modelo.dmem[0x3FC] == 7
    assert modelo.mem_escrita == {0x10, 0x3FC}


# TODO(nico): agregar los tests a medida que avanzan las tareas:
# - T4: branch hacia atrás y hacia adelante, jalr con dirección impar (AC1).
# - T5: loop infinito → TIMEOUT, 0x00000000 → ILLEGAL con su PC (AC2).
