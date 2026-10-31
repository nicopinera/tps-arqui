"""Golden model (US-108): un test por instrucción con valores borde y los casos de terminación."""

from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.isa.instrucciones import HALT_WORD
from riscv_toolkit.iss.golden_model import EstadoArquitectonico, GoldenModel, Motivo
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


# --- T4: saltos y lui -----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("programa", "esperado"),
    [
        ("beq x0, x0, fin\naddi x5, x0, 1\nfin: halt", 0),  # tomado: saltea el addi
        ("addi x1, x0, 1\nbeq x1, x0, fin\naddi x5, x0, 1\nfin: halt", 1),  # no tomado
        ("addi x1, x0, 1\nbne x1, x0, fin\naddi x5, x0, 1\nfin: halt", 0),  # tomado
        ("bne x0, x0, fin\naddi x5, x0, 1\nfin: halt", 1),  # no tomado
    ],
)
def test_branches(programa: str, esperado: int) -> None:
    assert _correr(programa).regs[5] == esperado


def test_loop_hacia_atras() -> None:
    modelo = _correr("addi x5, x0, 3\nloop: addi x6, x6, 1\naddi x5, x5, -1\nbne x5, x0, loop")
    assert modelo.regs[6] == 3  # 3 vueltas
    assert modelo.instrucciones_retiradas == 1 + 3 * 3


def test_jal_guarda_la_vuelta_y_jalr_vuelve() -> None:
    programa = """
        jal x1, funcion      # 0x00: x1 = 0x04
        addi x6, x0, 2       # 0x04: se ejecuta al volver
        halt                 # 0x08
    funcion:
        addi x5, x0, 7       # 0x0c
        jalr x0, 0(x1)       # 0x10: vuelve a 0x04
    """
    modelo = _correr(programa)
    assert modelo.regs[1] == 0x04
    assert (modelo.regs[5], modelo.regs[6]) == (7, 2)
    assert modelo.pc == 0x08


def test_jal_con_x0_no_guarda_nada() -> None:
    modelo = _correr("jal x0, fin\naddi x5, x0, 1\nfin: halt")
    assert modelo.regs[0] == 0
    assert modelo.regs[5] == 0


def test_jalr_borra_el_bit_0() -> None:
    # destino 0x0d & ~1 = 0x0c: saltea el addi de 0x08 (AC1)
    modelo = _correr("addi x1, x0, 0x0c\njalr x2, 1(x1)\naddi x5, x0, 1\nhalt")
    assert modelo.regs[5] == 0
    assert modelo.regs[2] == 0x08
    assert modelo.pc == 0x0C


def test_jalr_con_rd_igual_a_rs1() -> None:
    # si se escribiera x1 = 0x08 antes de leerlo, saltaría a 0x08 y ejecutaría el addi
    modelo = _correr("addi x1, x0, 0x0c\njalr x1, 0(x1)\naddi x5, x0, 1\nhalt")
    assert modelo.regs[5] == 0
    assert modelo.regs[1] == 0x08


def test_lui() -> None:
    modelo = _correr("lui x5, 0x12345\naddi x5, x5, 0x678\nlui x6, 0xFFFFF")
    assert modelo.regs[5] == 0x12345678
    assert modelo.regs[6] == 0xFFFFF000


def test_pc_negativo_da_la_vuelta() -> None:
    # jal a -4 desde 0: el PC queda en 0xFFFFFFFC y el fetch lee la última palabra de la IMEM
    modelo = GoldenModel([0xFFDFF06F])  # jal x0, -4
    assert modelo.step() is None
    assert modelo.pc == 0xFFFFFFFC
    assert modelo.step() is Motivo.HALTED  # imem[255] es el relleno


# --- T5: run y estado_final ----------------------------------------------------------------


def test_run_termina_en_halt() -> None:
    modelo = GoldenModel(ensamblar("addi x1, x0, 1\nhalt").palabras)
    assert modelo.run(100) is Motivo.HALTED
    assert modelo.instrucciones_retiradas == 1


def test_loop_infinito_termina_con_timeout() -> None:
    modelo = GoldenModel(ensamblar("loop: jal x0, loop").palabras)
    assert modelo.run(50) is Motivo.TIMEOUT  # AC2: no se cuelga
    assert modelo.instrucciones_retiradas == 50
    assert modelo.estado_final().motivo is Motivo.TIMEOUT


def test_palabra_cero_es_ilegal_con_su_pc() -> None:
    modelo = GoldenModel(ensamblar("addi x1, x0, 1\naddi x2, x0, 2\n.word 0").palabras)
    assert modelo.run(100) is Motivo.ILLEGAL  # AC2
    estado = modelo.estado_final()
    assert estado.pc == 0x08
    assert estado.regs[1:3] == (1, 2)  # lo anterior a la ilegal sí se ejecutó


def test_run_despues_de_terminar_repite_el_motivo() -> None:
    modelo = GoldenModel([])
    assert modelo.run(10) is Motivo.HALTED
    assert modelo.run(10) is Motivo.HALTED
    assert modelo.instrucciones_retiradas == 0


def test_estado_final_antes_de_run_falla() -> None:
    with pytest.raises(RuntimeError, match="run"):
        GoldenModel([]).estado_final()


def test_estado_final() -> None:
    modelo = GoldenModel(
        ensamblar("addi x1, x0, -1\nsw x1, 0x40(x0)\nsb x1, 0x11(x0)\nhalt").palabras
    )
    modelo.run(100)
    estado = modelo.estado_final()
    assert estado == EstadoArquitectonico(
        regs=(0, 0xFFFFFFFF) + (0,) * 30,
        mem_usada={0x10: 0x0000FF00, 0x40: 0xFFFFFFFF},  # AC3
        pc=0x0C,
        motivo=Motivo.HALTED,
    )
    assert list(estado.mem_usada) == [0x10, 0x40]  # orden creciente, como el snapshot


# --- T8: programas de integración (fixtures) -------------------------------------------------

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.mark.parametrize(
    ("programa", "regs", "mem_usada", "instrucciones"),
    [
        (
            "aritmetica.asm",
            {10: 93, 11: 0xFFFFFF95, 12: 1, 13: 0, 14: 0xFFFFFFFC, 15: 0xABCDE123},
            {},
            9,
        ),
        (
            "loads_stores.asm",
            {10: 0xFFFFFFFE, 11: 0xFE, 12: 0xFFFFFFFE, 13: 0xFFFE, 14: 0xFFFE007F},
            {0x100: 0xFFFFFFFE, 0x104: 0xFFFE007F},
            11,
        ),
        ("branches.asm", {5: 0x1C, 10: 0, 11: 2, 12: 3, 13: 4}, {}, 9),
        ("loop.asm", {1: 0, 2: 55}, {0x20: 55}, 33),
    ],
)
def test_programas(
    programa: str, regs: dict[int, int], mem_usada: dict[int, int], instrucciones: int
) -> None:
    modelo = GoldenModel(ensamblar((FIXTURES / programa).read_text("utf-8")).palabras)
    assert modelo.run(1000) is Motivo.HALTED
    estado = modelo.estado_final()
    assert {n: estado.regs[n] for n in regs} == regs
    assert estado.mem_usada == mem_usada
    assert modelo.instrucciones_retiradas == instrucciones
    assert modelo.advertencias == []
