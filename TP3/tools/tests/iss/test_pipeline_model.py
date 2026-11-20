"""Modelo del pipeline ciclo a ciclo (agregado US-306, pasos 2 a 5). Se verifica contra el
golden model (estado final), contra cuentas de ciclos a mano y contra los criterios de
aceptación de US-301, US-302 y US-303, que se escribieron antes de que existiera el modelo.

Cuenta de ciclos de un programa que termina (decisiones D2 y D4):
    ciclos = instrucciones ejecutadas (con el HALT) + 4 + stalls
             + 2·(branches tomados + jalr) + 1·jal
Las 4 son lo que tarda el HALT en recorrer IF → WB después de buscarse.
"""

import itertools
import re
from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.iss.golden_model import GoldenModel
from riscv_toolkit.iss.pipeline_model import FWD_BANCO, FWD_EX_MEM, FWD_MEM_WB, ModeloPipeline
from riscv_toolkit.protocol.comandos import EstadoDU, Motivo
from riscv_toolkit.protocol.snapshot import Snapshot

N3 = "nop\nnop\nnop\n"  # sin forwarding: 3 instrucciones de distancia, como en asm/tests/h2/


def correr(asm: str, max_ciclos: int = 5000) -> tuple[ModeloPipeline, list[Snapshot]]:
    """El modelo y el snapshot de cada ciclo (el 0 es el de antes del primer flanco)."""
    modelo = ModeloPipeline(ensamblar(asm).palabras)
    snaps = [modelo.snapshot()]
    while modelo.motivo is None and modelo.ciclos < max_ciclos:
        modelo.ciclo()
        snaps.append(modelo.snapshot())
    return modelo, snaps


def assert_igual_al_golden(asm: str) -> ModeloPipeline:
    modelo, _ = correr(asm)
    golden = GoldenModel(ensamblar(asm).palabras)
    golden.run(10_000)
    m, g = modelo.estado_final(), golden.estado_final()
    assert m.regs == g.regs
    assert m.mem_usada == g.mem_usada
    assert m.motivo == g.motivo
    return modelo


# --- Contra el golden model: un programa por grupo de instrucciones (US-210 AC1) ----------

PROGRAMAS = {
    "r_type": f"""
        addi x1, x0, 7
        addi x2, x0, -3
        {N3}
        add  x3, x1, x2
        sub  x4, x1, x2
        sll  x5, x1, x2
        slt  x6, x2, x1
        sltu x7, x2, x1
        xor  x8, x1, x2
        srl  x9, x2, x1
        sra  x10, x2, x1
        or   x11, x1, x2
        and  x12, x1, x2
        halt
    """,
    "i_arith_y_shifts": f"""
        addi  x1, x0, -100
        {N3}
        addi  x2, x1, 50
        slti  x3, x1, -99
        sltiu x4, x1, 5
        xori  x5, x1, -1
        ori   x6, x1, 15
        andi  x7, x1, 2032
        slli  x8, x1, 3
        srli  x9, x1, 4
        srai  x10, x1, 4
        halt
    """,
    "lui": """
        lui x1, 0xABCDE
        lui x2, 0xFFFFF
        halt
    """,
    "loads_stores": f"""
        lui  x1, 0x12345
        addi x2, x0, -2
        {N3}
        addi x1, x1, 0x678
        {N3}
        sw   x1, 0(x0)
        sh   x2, 4(x0)
        sb   x2, 9(x0)
        sb   x1, 10(x0)
        lw   x3, 0(x0)
        lh   x4, 4(x0)
        lhu  x5, 4(x0)
        lb   x6, 9(x0)
        lbu  x7, 9(x0)
        lb   x8, 1(x0)
        lhu  x9, 2(x0)
        halt
    """,
    "branches_y_loop": f"""
        addi x1, x0, 3
        addi x2, x0, 0
        {N3}
loop:   addi x2, x2, 5
        addi x1, x1, -1
        {N3}
        bne  x1, x0, loop
        beq  x0, x0, fin        # tomado: las dos siguientes se descartan
        addi x3, x0, 99
        addi x3, x0, 98
fin:    beq  x1, x2, nunca      # no tomado
        addi x4, x0, 4
        halt
nunca:  addi x5, x0, 1
        halt
    """,
    "jal_jalr": f"""
        addi x10, x0, 3
        jal  x1, doble
        {N3}
        addi x11, x10, 1
        halt
doble:  add  x10, x10, x10
        {N3}
        ret
    """,
}


@pytest.mark.parametrize("asm", PROGRAMAS.values(), ids=PROGRAMAS.keys())
def test_mismo_estado_final_que_el_golden_model(asm: str) -> None:
    assert_igual_al_golden(asm)


def test_ilegal_termina_con_motivo_illegal() -> None:
    modelo = assert_igual_al_golden("addi x1, x0, 5\n.word 0xffffffff\naddi x2, x0, 9\nhalt\n")
    assert modelo.motivo is Motivo.ILLEGAL


# --- Cuentas de ciclos (agregado §7) --------------------------------------------------------


@pytest.mark.parametrize(
    ("asm", "ciclos"),
    [
        ("addi x1, x0, 1\naddi x2, x0, 2\naddi x3, x0, 3\nhalt\n", 4 + 4),
        ("beq x0, x0, fin\naddi x1, x0, 1\naddi x1, x0, 2\nfin: halt\n", 2 + 4 + 2),
        ("beq x1, x2, fin\nfin: halt\n", 2 + 4 + 2),  # tomado aunque salte a la siguiente
        ("bne x0, x0, fin\nhalt\nfin: halt\n", 2 + 4),  # no tomado: sin penalidad
        ("jal x0, fin\naddi x1, x0, 1\nfin: halt\n", 2 + 4 + 1),
        (f"addi x1, x0, 24\n{N3}jalr x0, 0(x1)\naddi x5, x0, 1\nhalt\n", 6 + 4 + 2),
    ],
    ids=["sin_saltos", "beq_tomado", "beq_a_la_siguiente", "bne_no_tomado", "jal", "jalr"],
)
def test_ciclos(asm: str, ciclos: int) -> None:
    modelo, _ = correr(asm)
    assert modelo.motivo is Motivo.HALTED
    assert modelo.ciclos == ciclos


def test_un_loop_infinito_no_termina() -> None:
    modelo = ModeloPipeline(ensamblar("loop: jal x0, loop\n").palabras)
    assert modelo.correr(100) is None
    assert modelo.ciclos == 100


# --- El pipeline por dentro -----------------------------------------------------------------


def test_cada_instruccion_avanza_una_etapa_por_ciclo() -> None:
    _, snaps = correr("addi x1, x0, 1\naddi x2, x0, 2\naddi x3, x0, 3\nhalt\n")
    # En el ciclo k, la instrucción i está en IF/ID si k = i+1, en ID/EX si k = i+2, …
    pcs = [
        tuple(
            latch.pc_plus4 - 4 if latch.valid else None
            for latch in (s.if_id, s.id_ex, s.ex_mem, s.mem_wb)
        )
        for s in snaps
    ]
    assert pcs[:5] == [
        (None, None, None, None),
        (0x0, None, None, None),
        (0x4, 0x0, None, None),
        (0x8, 0x4, 0x0, None),
        (0xC, 0x8, 0x4, 0x0),  # pipeline lleno
    ]
    assert snaps[-1].regs[1:4] == (1, 2, 3)


def test_los_latches_llevan_las_senales_de_control() -> None:
    _, snaps = correr(f"addi x1, x0, 8\n{N3}lw x2, 4(x1)\nhalt\n")
    id_ex = snaps[6].id_ex  # lw es la instrucción 4: entra a ID/EX en el flanco 6
    assert (id_ex.rd, id_ex.rs1, id_ex.imm, id_ex.rs1_data) == (2, 1, 4, 8)
    assert (id_ex.mem_read, id_ex.reg_write, id_ex.alu_src, id_ex.result_src) == (
        True, True, True, 1,
    )  # fmt: skip
    assert snaps[7].ex_mem.alu_result == 12  # la dirección: 8 + 4


def test_bypass_del_banco_con_dos_nops() -> None:
    # addi en WB y add en ID en el mismo ciclo: ID lee el valor que WB está escribiendo.
    modelo = assert_igual_al_golden("addi x1, x0, 5\nnop\nnop\nadd x2, x1, x1\nhalt\n")
    assert modelo.regs[2] == 10


def test_con_un_nop_el_dato_llega_por_forwarding_desde_mem_wb() -> None:
    # Sin la Forwarding Unit (paso 2) daba 0: addi todavía estaba en MEM cuando add leyó x1.
    modelo = assert_igual_al_golden("addi x1, x0, 5\nnop\nadd x2, x1, x1\nhalt\n")
    assert modelo.regs[2] == 10


def test_branch_tomado_hace_flush_de_if_id_e_id_ex() -> None:
    _, snaps = correr("beq x0, x0, fin\naddi x1, x0, 1\naddi x1, x0, 2\nfin: halt\n")
    r = snaps[2].riesgos  # beq en EX
    assert (r.flush_if_id, r.flush_id_ex) == (True, True)
    assert not snaps[3].if_id.valid
    assert not snaps[3].id_ex.valid
    assert snaps[3].pc == 0xC  # el PC apunta al destino (fin): IF lo busca en este ciclo


def test_jal_hace_flush_solo_de_if_id() -> None:
    modelo, snaps = correr("jal x1, fin\naddi x2, x0, 1\nfin: halt\n")
    r = snaps[1].riesgos  # jal en ID
    assert (r.flush_if_id, r.flush_id_ex) == (True, False)
    assert snaps[2].id_ex.jump  # jal sigue bajando: tiene que escribir x1
    assert modelo.regs[1:3] == [4, 0]


def test_al_terminar_el_pipeline_queda_vacio() -> None:
    addi_x5 = ensamblar("addi x5, x0, 5\n").palabras[0]
    modelo, snaps = correr("addi x1, x0, 1\nhalt\naddi x5, x0, 5\n")
    final = snaps[-1]
    assert (final.motivo, final.estado) == (Motivo.HALTED, EstadoDU.HALTED)
    assert not any(latch.valid for latch in (final.if_id, final.id_ex, final.ex_mem, final.mem_wb))
    # US-210 AC3: lo que sigue al HALT en memoria nunca llega a EX.
    assert all(not (s.id_ex.valid and s.id_ex.instr == addi_x5) for s in snaps)
    assert modelo.pc == 0x4 + 4  # D3: congelado en (HALT) + 4
    ciclos = modelo.ciclos
    modelo.ciclo()  # terminado: el núcleo ignora el enable
    assert modelo.ciclos == ciclos


@pytest.mark.parametrize("especulativa", ["halt", ".word 0xffffffff"])
def test_halt_o_ilegal_despues_de_un_branch_tomado_no_detiene(especulativa: str) -> None:
    # US-303 AC6 y AC9: estaban en ID cuando el beq redirigió desde EX → se descartan.
    modelo = assert_igual_al_golden(
        f"beq x0, x0, fin\n{especulativa}\nnop\nfin: addi x1, x0, 1\nhalt\n"
    )
    assert (modelo.motivo, modelo.regs[1]) == (Motivo.HALTED, 1)


def test_el_programa_no_entra_en_la_imem() -> None:
    with pytest.raises(ValueError, match="IMEM"):
        ModeloPipeline([0] * 3, imem_words_max=2)


def test_estado_final_antes_de_terminar_falla() -> None:
    with pytest.raises(RuntimeError, match="no terminó"):
        ModeloPipeline([]).estado_final()


# --- Paso 3: Forwarding Unit (US-301) -------------------------------------------------------


def en_ex(snaps: list[Snapshot], instr: str) -> Snapshot:
    """El snapshot del ciclo en que `instr` está en EX (en ID/EX, válida)."""
    palabra = ensamblar(instr + "\n").palabras[0]
    return next(s for s in snaps if s.id_ex.valid and s.id_ex.instr == palabra)


def fwd(snaps: list[Snapshot], instr: str) -> tuple[int, int]:
    r = en_ex(snaps, instr).riesgos
    return r.fwd_a, r.fwd_b


def test_ac1_desde_ex_mem() -> None:
    _, snaps = correr("addi x2, x0, 3\nadd x1, x2, x2\nsub x3, x1, x0\nhalt\n")
    assert fwd(snaps, "sub x3, x1, x0") == (FWD_EX_MEM, FWD_BANCO)


def test_ac2_desde_mem_wb() -> None:
    _, snaps = correr("addi x1, x0, 3\nnop\nadd x2, x1, x0\nhalt\n")
    assert fwd(snaps, "add x2, x1, x0") == (FWD_MEM_WB, FWD_BANCO)


def test_ac3_doble_coincidencia_gana_ex_mem() -> None:
    modelo, snaps = correr("addi x1, x0, 1\naddi x1, x0, 2\nadd x2, x1, x1\nhalt\n")
    assert fwd(snaps, "add x2, x1, x1") == (FWD_EX_MEM, FWD_EX_MEM)
    assert modelo.regs[2] == 4  # el más nuevo (2), no el viejo (1)


def test_ac4_x0_nunca() -> None:
    modelo, snaps = correr("addi x0, x0, 5\nadd x2, x0, x0\nhalt\n")
    assert fwd(snaps, "add x2, x0, x0") == (FWD_BANCO, FWD_BANCO)
    assert modelo.regs[2] == 0


def test_ac5_hacia_store_data() -> None:
    modelo = assert_igual_al_golden("addi x5, x0, 7\nsw x5, 8(x0)\nhalt\n")
    assert modelo.snapshot().mem_usada == {8: 7}


def test_ac6_resultado_de_jal() -> None:
    modelo = assert_igual_al_golden("jal x1, f\nhalt\nf: addi x2, x1, 0\nhalt\n")
    assert modelo.regs[2] == 4  # PC + 4 del jal, desde MEM/WB


def test_ac7_hacia_branch_cmp() -> None:
    modelo, snaps = correr(
        f"addi x2, x0, 1\n{N3}addi x1, x0, 1\nbeq x1, x2, salto\naddi x3, x0, 9\nsalto: halt\n"
    )
    r = next(s for s in snaps if s.id_ex.valid and s.id_ex.branch).riesgos  # beq en EX
    assert (r.fwd_a, r.fwd_b) == (FWD_EX_MEM, FWD_BANCO)
    assert modelo.regs[3] == 0  # comparó con el x1 nuevo: saltó


# --- Paso 4: Hazard Unit (US-302, US-303) y stop_fetch --------------------------------------


def stalls(snaps: list[Snapshot]) -> int:
    return sum(s.riesgos.stall for s in snaps)


@pytest.mark.parametrize(
    ("asm", "esperados"),
    [
        ("lw x1, 0(x2)\nadd x3, x1, x4\nhalt\n", 1),  # AC1
        ("lw x1, 0(x2)\naddi x5, x0, 1\nadd x3, x1, x4\nhalt\n", 0),  # AC2: alcanza forwarding
        ("lw x1, 0(x2)\nlui x1, 5\nhalt\n", 0),  # AC3: lui no lee rs1
        ("lw x1, 0(x2)\nsw x1, 4(x0)\nhalt\n", 1),  # AC4: no hay forwarding MEM→MEM
        ("lw x0, 0(x2)\nadd x3, x0, x0\nhalt\n", 0),  # AC5: x0
        ("lw x1, 0(x2)\nbeq x1, x0, fin\naddi x3, x0, 1\nfin: halt\n", 1),  # US-303 AC5
    ],
    ids=["ac1", "ac2_independiente", "ac3_lui", "ac4_store", "ac5_x0", "branch_tras_load"],
)
def test_load_use(asm: str, esperados: int) -> None:
    # Con la memoria escrita antes, para que el load traiga algo distinto de 0.
    preparado = f"addi x9, x0, 6\n{N3}sw x9, 0(x0)\naddi x2, x0, 0\n{N3}" + asm
    assert_igual_al_golden(preparado)
    _, snaps = correr(preparado)
    assert stalls(snaps) == esperados


def test_el_stall_congela_pc_e_if_id_y_mete_una_burbuja() -> None:
    _, snaps = correr("lw x1, 0(x0)\nadd x3, x1, x1\nhalt\n")
    i = next(i for i, s in enumerate(snaps) if s.riesgos.stall)
    antes, despues = snaps[i], snaps[i + 1]
    assert despues.pc == antes.pc  # el PC no avanzó
    assert despues.if_id == antes.if_id  # el add sigue en ID
    assert not despues.id_ex.valid  # burbuja en EX
    assert despues.ex_mem.mem_read  # el lw siguió a MEM
    assert fwd(snaps, "add x3, x1, x1") == (FWD_MEM_WB, FWD_MEM_WB)  # después, desde MEM/WB


def test_ac8_branch_en_ex_gana_a_jal_en_id() -> None:
    modelo = assert_igual_al_golden(
        "beq x0, x0, bien\njal x0, mal\nbien: addi x1, x0, 1\nhalt\nmal: addi x2, x0, 2\nhalt\n"
    )
    assert modelo.regs[1:3] == [1, 0]


def test_stop_fetch_vacia_el_pipeline_sin_buscar_mas() -> None:
    # US-210 AC6 y US-303 AC10: aunque haya un branch tomado en EX, no busca el destino.
    modelo = ModeloPipeline(ensamblar("loop: addi x1, x1, 1\nbeq x0, x0, loop\n").palabras)
    modelo.correr(20)
    modelo.stop_fetch = True
    ciclos = 0
    while not modelo.vacio:
        modelo.ciclo()
        ciclos += 1
        assert not modelo.snapshot().riesgos.stall
    assert ciclos <= 3
    pc = modelo.pc
    modelo.ciclo()
    assert (modelo.pc, modelo.vacio, modelo.motivo) == (pc, True, None)


# --- Paso 5: todos los programas del repo contra el golden model ----------------------------

ASM = Path(__file__).resolve().parents[3] / "asm"
FIXTURES_ASM = Path(__file__).resolve().parents[1] / "fixtures" / "asm"
PROGRAMAS_REPO = sorted(
    p for p in ASM.rglob("*.asm") if "errores" not in p.parts and p.stem != "infinite_loop"
)


def test_hay_programas_en_el_repo() -> None:
    assert len(PROGRAMAS_REPO) >= 9


@pytest.mark.parametrize("ruta", PROGRAMAS_REPO, ids=lambda p: p.stem)
def test_programa_del_repo_igual_al_golden(ruta: Path) -> None:
    assert_igual_al_golden(ruta.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    ("nombre", "ciclos"),
    [
        ("load_use", 9 + 4 + 1),  # 9 instrucciones, 1 stall (lw x2 → add x2)
        ("fwd_ex_mem", 14 + 4),  # todo por forwarding: 0 stalls
        ("llamadas", 9 + 4 + 2 * 1 + 2 * 2),  # 2 jal (+1 cada uno) y 2 ret (+2)
        ("branch_taken", 20 + 4 + 2 + 3 * 2 + 1),  # beq tomado, 3 bne tomados y el j
    ],
)
def test_ciclos_de_los_programas_de_riesgos(nombre: str, ciclos: int) -> None:
    ruta = FIXTURES_ASM / f"{nombre}.asm"
    modelo, _ = correr(ruta.read_text(encoding="utf-8"))
    assert modelo.ciclos == ciclos


@pytest.mark.parametrize("ruta", sorted((ASM / "riesgos").glob("*.asm")), ids=lambda p: p.stem)
def test_ciclos_del_encabezado_de_asm_riesgos(ruta: Path) -> None:
    # Cada programa de estudio dice en su encabezado cuántos ciclos tarda: tiene que ser cierto.
    texto = ruta.read_text(encoding="utf-8")
    dice = re.search(r"^# Ciclos: (\d+)", texto, re.MULTILINE)
    assert dice is not None, "falta la línea '# Ciclos: N'"
    modelo, _ = correr(texto)
    assert modelo.ciclos == int(dice.group(1))


# --- Cables y desde_snapshot (vista Datapath de la GUI) --------------------------------------


@pytest.mark.parametrize("ruta", PROGRAMAS_REPO, ids=lambda p: p.stem)
def test_desde_snapshot_reproduce_el_ciclo_siguiente(ruta: Path) -> None:
    # Si el estado reconstruido desde un snapshot avanza al snapshot siguiente, los cables que
    # se calculan desde él son los del ciclo de verdad (incluido halt_fetch, que se deduce).
    palabras = ensamblar(ruta.read_text(encoding="utf-8")).palabras
    _, snaps = correr(ruta.read_text(encoding="utf-8"))
    for antes, despues in itertools.pairwise(snaps):
        modelo = ModeloPipeline.desde_snapshot(antes, palabras)
        modelo.ciclo()
        assert modelo.snapshot() == despues, f"ciclo {antes.ciclos}"


def test_cables_del_load_use() -> None:
    asm = (FIXTURES_ASM / "load_use.asm").read_text(encoding="utf-8")
    _, snaps = correr(asm)
    palabras = ensamblar(asm).palabras

    def cables(ciclo: int) -> dict[str, int]:
        return ModeloPipeline.desde_snapshot(snaps[ciclo], palabras).cables()

    c4 = cables(4)  # lw x2 en EX, add x2,x2,x2 en ID: stall
    assert (c4["StallF"], c4["StallD"], c4["FlushE"], c4["FlushD"]) == (1, 1, 1, 0)
    assert (c4["rs1D"], c4["uses_rs1"], c4["pc_sel"]) == (2, 1, 0b00)
    assert c4["alu_resultE"] == 0  # la dirección del lw: 0(x0)
    c6 = cables(6)  # add en EX con x2 = 7 desde MEM/WB (el dato del lw)
    assert (c6["srcA"], c6["srcB"], c6["alu_resultE"]) == (7, 7, 14)
    assert c6["ResultW"] == 7
    assert c6["StallF"] == 0
