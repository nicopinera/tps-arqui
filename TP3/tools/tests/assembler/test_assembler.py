"""Ensamblador de dos pasadas (US-106)."""

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.isa.formatos import CamposB, CamposJ, encode_b, encode_j
from riscv_toolkit.isa.instrucciones import HALT_WORD
from riscv_toolkit.protocol.comandos import IMEM_DEPTH

HALT_AGREGADO = "el programa no termina en halt: se agregó uno al final"


def _palabras(texto: str) -> list[int]:
    return ensamblar(texto).palabras


# --- Una prueba por instrucción (AC1) ----------------------------------------------------

# Palabras calculadas a mano campo por campo (ver docs/interfaces/formatos.md); beq, bne y jal
# llevan etiqueta y se prueban más abajo.
UNA_POR_INSTRUCCION = [
    ("add x3, x1, x2", 0x002081B3),
    ("sub x5, x6, x7", 0x407302B3),
    ("sll x1, x2, x3", 0x003110B3),
    ("slt x1, x2, x3", 0x003120B3),
    ("sltu x1, x2, x3", 0x003130B3),
    ("xor x1, x2, x3", 0x003140B3),
    ("srl x1, x2, x3", 0x003150B3),
    ("sra x1, x2, x3", 0x403150B3),
    ("or x1, x2, x3", 0x003160B3),
    ("and x1, x2, x3", 0x003170B3),
    ("addi x1, x0, 5", 0x00500093),
    ("slti x1, x2, -1", 0xFFF12093),
    ("sltiu x1, x2, 1", 0x00113093),
    ("xori x1, x2, -1", 0xFFF14093),
    ("ori x1, x2, 0x7FF", 0x7FF16093),
    ("andi x1, x2, -2048", 0x80017093),
    ("slli x1, x2, 31", 0x01F11093),
    ("srli x1, x2, 1", 0x00115093),
    ("srai x1, x2, 3", 0x40315093),
    ("lb x1, 0(x2)", 0x00010083),
    ("lh x1, 2(x2)", 0x00211083),
    ("lw x5, -4(x2)", 0xFFC12283),
    ("lbu x1, 2047(x2)", 0x7FF14083),
    ("lhu x1, -2048(x2)", 0x80015083),
    ("jalr x1, 8(x5)", 0x008280E7),
    ("sb x1, 0(x2)", 0x00110023),
    ("sh x1, 2(x2)", 0x00111123),
    ("sw x5, -4(x2)", 0xFE512E23),
    ("lui x1, 0x12345", 0x123450B7),
    ("lui x31, 0xFFFFF", 0xFFFFFFB7),
    ("halt", HALT_WORD),
]


@pytest.mark.parametrize(("linea", "palabra"), UNA_POR_INSTRUCCION, ids=lambda x: str(x))
def test_una_instruccion(linea: str, palabra: int) -> None:
    assert _palabras(linea)[0] == palabra


# --- Etiquetas y offsets (AC3) ------------------------------------------------------------


def test_offsets_hacia_adelante_y_hacia_atras() -> None:
    texto = """
    atras:    beq x1, x2, adelante   # 0x00 → 0x08: +8
              bne x1, x0, atras      # 0x04 → 0x00: -4
    adelante: jal x1, atras          # 0x08 → 0x00: -8
              jal x0, fin            # 0x0C → 0x10: +4
    fin:      halt
    """
    assert _palabras(texto) == [
        encode_b(CamposB(0b1100011, 0b000, 1, 2, 8)),
        encode_b(CamposB(0b1100011, 0b001, 1, 0, -4)),
        encode_j(CamposJ(0b1101111, 1, -8)),
        encode_j(CamposJ(0b1101111, 0, 4)),
        HALT_WORD,
    ]


def test_salto_a_si_mismo() -> None:
    assert _palabras("aca: beq x0, x0, aca")[0] == encode_b(CamposB(0b1100011, 0, 0, 0, 0))


def test_ejemplo_de_la_guia() -> None:
    texto = """        addi x5, x0, 3
loop:   addi x5, x5, -1
        bne  x5, x0, loop
        j    fin
        nop
fin:    halt"""
    imagen = ensamblar(texto)
    assert imagen.palabras == [0x00300293, 0xFFF28293, 0xFE029EE3, 0x0080006F, 0x13, HALT_WORD]
    assert imagen.simbolos == {"loop": 0x04, "fin": 0x14}
    assert imagen.mapa_lineas == {0x00: 1, 0x04: 2, 0x08: 3, 0x0C: 4, 0x10: 5, 0x14: 6}
    assert imagen.expansiones == {0x0C: "jal x0, fin", 0x10: "addi x0, x0, 0"}
    assert imagen.advertencias == []


def test_etiqueta_sola_apunta_a_la_proxima_instruccion() -> None:
    imagen = ensamblar("nop\ninicio:\n\n# comentario\n  addi x1, x1, 1\nhalt")
    assert imagen.simbolos == {"inicio": 4}
    assert imagen.mapa_lineas == {0: 1, 4: 5, 8: 6}


def test_varias_etiquetas_en_la_misma_direccion() -> None:
    assert ensamblar("a:\nb: nop\nhalt").simbolos == {"a": 0, "b": 0}


def test_etiqueta_despues_del_halt() -> None:
    # Apunta fuera del programa, al relleno de HALT de la IMEM (ADR-009): se acepta.
    imagen = ensamblar("j fin\nhalt\nfin:")
    assert imagen.simbolos == {"fin": 8}
    assert imagen.palabras[0] == encode_j(CamposJ(0b1101111, 0, 8))


def test_etiqueta_duplicada() -> None:
    with pytest.raises(
        ErrorEnsamblado, match=r"^línea 3: etiqueta 'a' duplicada \(ya definida en la línea 1\)"
    ):
        ensamblar("a: nop\nnop\na: halt")


def test_etiqueta_inexistente() -> None:
    with pytest.raises(ErrorEnsamblado, match=r"^línea 2: etiqueta inexistente 'fin'"):
        ensamblar("nop\nbeq x1, x2, fin\nhalt")


def test_las_etiquetas_distinguen_mayusculas() -> None:
    with pytest.raises(ErrorEnsamblado, match="etiqueta inexistente 'Fin'"):
        ensamblar("fin: j Fin")


# --- Pseudoinstrucciones (AC6) ------------------------------------------------------------


@pytest.mark.parametrize(
    ("linea", "expansion", "palabra"),
    [
        ("nop", "addi x0, x0, 0", 0x00000013),
        ("mv x5, x6", "addi x5, x6, 0", 0x00030293),
        ("ret", "jalr x0, 0(x1)", 0x00008067),
        ("aca: j aca", "jal x0, aca", 0x0000006F),
    ],
)
def test_pseudoinstrucciones(linea: str, expansion: str, palabra: int) -> None:
    imagen = ensamblar(linea)
    assert imagen.palabras[0] == palabra
    assert imagen.expansiones == {0: expansion}


def test_la_pseudo_conserva_su_etiqueta_y_su_linea() -> None:
    imagen = ensamblar("halt\nvolver: ret")
    assert imagen.simbolos == {"volver": 4}
    assert imagen.mapa_lineas[4] == 2


# --- HALT final (R-PR-1) y tamaño (AC5, R-PR-2) --------------------------------------------


def test_no_agrega_halt_si_ya_termina_en_halt() -> None:
    imagen = ensamblar("nop\nhalt\n# fin\n")
    assert imagen.palabras == [0x13, HALT_WORD]
    assert imagen.advertencias == []


def test_agrega_halt_si_falta() -> None:
    imagen = ensamblar("nop")
    assert imagen.palabras == [0x13, HALT_WORD]
    assert imagen.advertencias == [HALT_AGREGADO]
    assert imagen.mapa_lineas == {0: 1}  # el HALT agregado no viene de ninguna línea


def test_halt_en_el_medio_no_cuenta_como_final() -> None:
    imagen = ensamblar("halt\nsubrutina: ret")
    assert imagen.palabras[-1] == HALT_WORD
    assert len(imagen.palabras) == 3
    assert imagen.advertencias == [HALT_AGREGADO]


def test_programa_vacio() -> None:
    imagen = ensamblar("# nada\n")
    assert imagen.palabras == [HALT_WORD]
    assert imagen.advertencias == [HALT_AGREGADO]


def test_entra_justo_en_la_imem() -> None:
    assert len(_palabras("nop\n" * (IMEM_DEPTH - 1) + "halt")) == IMEM_DEPTH


def test_no_entra_por_el_halt_agregado() -> None:
    mensaje = rf"^línea {IMEM_DEPTH}: el programa ocupa {IMEM_DEPTH + 1} palabras"
    with pytest.raises(ErrorEnsamblado, match=mensaje):
        ensamblar("nop\n" * IMEM_DEPTH)


def test_no_entra_con_halt_propio() -> None:
    # La línea del error es la de la primera instrucción que queda afuera.
    with pytest.raises(ErrorEnsamblado, match=rf"^línea {IMEM_DEPTH + 1}: "):
        ensamblar("nop\n" * IMEM_DEPTH + "halt")


# --- .word -------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("linea", "palabra"),
    [(".word 0xDEADBEEF", 0xDEADBEEF), (".word -1", 0xFFFFFFFF), (".word 0", 0)],
)
def test_word(linea: str, palabra: int) -> None:
    assert _palabras(linea)[0] == palabra


def test_word_no_cuenta_como_halt() -> None:
    assert ensamblar(".word 0x0000000B").advertencias == [HALT_AGREGADO]


# --- Errores de rango (AC4) ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("linea", "mensaje"),
    [
        ("slli x1, x1, 32", r"shamt fuera de rango: 32 \(0\.\.31\)"),
        ("srai x1, x1, -1", r"shamt fuera de rango: -1 \(0\.\.31\)"),
        ("lui x1, 0x100000", r"imm de lui fuera de rango: 1048576 \(0\.\.1048575\)"),
        ("lui x1, -1", "imm de lui fuera de rango: -1"),
        (".word 0x100000000", r"\.word fuera de rango: 4294967296"),
        ("addi x1, x1, 2048", r"imm fuera de rango: 2048 \(-2048\.\.2047\)"),  # de formatos.py
        ("sw x1, -2049(x2)", "imm fuera de rango: -2049"),
        ("jalr x0, 4096(x1)", "imm fuera de rango: 4096"),
    ],
)
def test_fuera_de_rango(linea: str, mensaje: str) -> None:
    with pytest.raises(ErrorEnsamblado, match=f"^línea 2: {mensaje}"):
        ensamblar(f"nop\n{linea}")


def test_los_errores_de_formatos_se_encadenan() -> None:
    with pytest.raises(ErrorEnsamblado) as info:
        ensamblar("addi x1, x1, 5000")
    assert isinstance(info.value.__cause__, ValueError)
