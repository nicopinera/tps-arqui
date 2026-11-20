"""Mapeo columna → instrucción y marcas de riesgo de la vista del pipeline (US-502)."""

from dataclasses import fields, replace

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.isa.instrucciones import HALT_WORD
from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    RiesgosCiclo,
    Snapshot,
)
from riscv_toolkit.session.debug_session import DebugSession
from riscv_toolkit.ui.pipeline import (
    ETAPAS,
    LATCHES,
    Columna,
    campos_latch,
    columnas_pipeline,
    destino_salto,
    explicar,
    latches,
    senales,
)

# 0x00 lw · 0x04 add (usa x1: load-use) · 0x08 beq tomado → 0x10 · 0x0c addi x3 · 0x10 addi x4
PROGRAMA = ensamblar(
    "lw x1, 0(x0)\nadd x2, x1, x1\nbeq x0, x0, fin\naddi x3, x0, 3\nfin: addi x4, x0, 4\nhalt\n"
).palabras
LW, ADD, BEQ, ADDI3, ADDI4, HALT = PROGRAMA

VACIO = Snapshot(EstadoDU.STEPPING, None, 0, 0, RiesgosCiclo(), (0,) * 32,
                 LatchIFID(), LatchIDEX(), LatchEXMEM(), LatchMEMWB())  # fmt: skip


def snap(
    pc: int,
    if_id: tuple[int, int] | None = None,
    id_ex: tuple[int, int] | None = None,
    ex_mem: tuple[int, int] | None = None,
    mem_wb: tuple[int, int] | None = None,
    riesgos: RiesgosCiclo | None = None,
) -> Snapshot:
    """Snapshot con (pc, instr) en cada latch; None = burbuja."""
    return replace(
        VACIO,
        pc=pc,
        riesgos=riesgos or RiesgosCiclo(),
        if_id=LatchIFID(if_id[0], if_id[0] + 4, if_id[1], True) if if_id else LatchIFID(),
        id_ex=LatchIDEX(pc=id_ex[0], instr=id_ex[1], valid=True) if id_ex else LatchIDEX(),
        ex_mem=LatchEXMEM(pc_plus4=ex_mem[0] + 4, instr=ex_mem[1], valid=True)
        if ex_mem
        else LatchEXMEM(),
        mem_wb=LatchMEMWB(pc_plus4=mem_wb[0] + 4, instr=mem_wb[1], valid=True)
        if mem_wb
        else LatchMEMWB(),
    )


def textos(columnas: list[Columna]) -> list[str]:
    return [c.texto if not c.burbuja else "-" for c in columnas]


# --- Mapeo ---------------------------------------------------------------------------------


def test_cada_columna_sale_de_su_latch_y_if_del_pc() -> None:
    s = snap(0x10, if_id=(0x0C, ADDI3), id_ex=(0x08, BEQ), ex_mem=(0x04, ADD), mem_wb=(0, LW))
    cols = columnas_pipeline(s, PROGRAMA)
    assert [c.etapa for c in cols] == list(ETAPAS)
    assert [c.pc for c in cols] == [0x10, 0x0C, 0x08, 0x04, 0x00]
    assert textos(cols) == [
        "addi x4, x0, 4", "addi x3, x0, 3", "beq x0, x0, 0x10", "add x2, x1, x1", "lw x1, 0(x0)",
    ]  # fmt: skip


def test_burbujas_donde_valid_es_cero() -> None:
    cols = columnas_pipeline(snap(0x04, if_id=(0, LW)), PROGRAMA)
    assert [c.burbuja for c in cols] == [False, False, True, True, True]


@pytest.mark.parametrize("estado", [EstadoDU.IDLE, EstadoDU.HALTED])
def test_sin_ejecucion_if_tambien_esta_vacia(estado: EstadoDU) -> None:
    cols = columnas_pipeline(replace(snap(0x14), estado=estado), PROGRAMA)
    assert all(c.burbuja for c in cols)


def test_if_fuera_del_programa_es_halt() -> None:
    (if_,) = columnas_pipeline(snap(0x40), PROGRAMA)[:1]
    assert if_.halt
    assert if_.texto == "halt"
    assert HALT_WORD == HALT


def test_if_sin_programa_conocido() -> None:
    (if_,) = columnas_pipeline(snap(0x08), None)[:1]
    assert (if_.pc, if_.texto, if_.burbuja) == (0x08, "?", False)


def test_halt_e_ilegal_se_marcan() -> None:
    s = snap(0x18, if_id=(0x14, HALT), id_ex=(0x10, 0xFFFFFFFF))
    cols = columnas_pipeline(s, PROGRAMA)
    assert cols[1].halt
    assert not cols[1].ilegal
    assert cols[2].ilegal
    assert not cols[2].halt


# --- Criterios de aceptación ---------------------------------------------------------------


def test_ac1_load_use_stall_y_burbuja_en_ex() -> None:
    # Ciclo del stall: lw en EX y su dependiente (add) en ID.
    stall = snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW), riesgos=RiesgosCiclo(stall=True))
    cols = columnas_pipeline(stall, PROGRAMA)
    assert [c.congelada for c in cols] == [True, True, False, False, False]
    # Ciclo siguiente: burbuja en EX y la misma instrucción en ID (dos ciclos seguidos).
    despues = snap(0x08, if_id=(0x04, ADD), ex_mem=(0x00, LW))
    cols2 = columnas_pipeline(despues, PROGRAMA)
    assert cols2[2].burbuja
    assert cols2[1].texto == cols[1].texto == "add x2, x1, x1"


def test_ac2_branch_tomado_anula_if_e_id() -> None:
    s = snap(
        0x10,
        if_id=(0x0C, ADDI3),
        id_ex=(0x08, BEQ),
        riesgos=RiesgosCiclo(flush_if_id=True, flush_id_ex=True),
    )
    cols = columnas_pipeline(s, PROGRAMA)
    assert [c.anulada for c in cols] == [True, True, False, False, False]


@pytest.mark.parametrize(
    ("fwd_a", "fwd_b", "en_ex", "fuente"),
    [
        (2, 0, ("A ← EX/MEM",), {"MEM": ("→ A",)}),
        (0, 1, ("B ← MEM/WB",), {"WB": ("→ B",)}),
        (2, 2, ("A ← EX/MEM", "B ← EX/MEM"), {"MEM": ("→ A", "→ B")}),
        (0, 0, (), {}),
    ],
)
def test_ac3_forwarding_en_ex_y_en_la_fuente(
    fwd_a: int, fwd_b: int, en_ex: tuple[str, ...], fuente: dict[str, tuple[str, ...]]
) -> None:
    s = snap(0x0C, id_ex=(0x08, ADD), ex_mem=(0x04, LW), mem_wb=(0x00, LW),
             riesgos=RiesgosCiclo(fwd_a=fwd_a, fwd_b=fwd_b))  # fmt: skip
    cols = {c.etapa: c for c in columnas_pipeline(s, PROGRAMA)}
    assert cols["EX"].marcas == en_ex
    for etapa in ("IF", "ID", "MEM", "WB"):
        assert cols[etapa].marcas == fuente.get(etapa, ())


def test_ac4_todos_los_campos_con_nombre() -> None:
    s = snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW))
    for nombre, latch in latches(s).items():
        filas = campos_latch(latch)
        assert [f[0] for f in filas] == [f.name for f in fields(latch)], nombre
    assert list(latches(s)) == list(LATCHES)


def test_ac4_formato_de_los_valores() -> None:
    filas = {c: (h, d) for c, h, d in campos_latch(LatchIDEX(imm=0xFFFFFFFC, rd=5, valid=True))}
    assert filas["imm"] == ("0xfffffffc", "4294967292 (-4)")
    assert filas["rd"] == ("0x5", "5")
    assert filas["valid"] == ("0x1", "1")
    assert filas["pc"] == ("0x00000000", "0")


def test_ac5_if_despues_de_un_salto_tomado_es_el_destino() -> None:
    # beq resuelto: el PC ya apunta a `fin` (0x10), y IF muestra esa, no la de 0x0c.
    s = snap(0x10, if_id=(0x0C, ADDI3), id_ex=(0x08, BEQ))
    assert columnas_pipeline(s, PROGRAMA)[0].texto == "addi x4, x0, 4"


def test_con_el_fake_se_ven_el_stall_el_forwarding_y_el_flush() -> None:
    # El fake corre el modelo del pipeline: PROGRAMA tiene un load-use y un beq tomado.
    sesion = DebugSession(FakeTransport())
    sesion.load(PROGRAMA)
    s = [sesion.dump(), *(sesion.step() for _ in range(6))]
    assert s[2].riesgos.stall  # lw en EX, add en ID
    cols = columnas_pipeline(s[3], PROGRAMA)
    assert [c.pc for c in cols] == [0x08, 0x04, None, 0x00, None]  # add sigue en ID; burbuja
    assert cols[2].burbuja
    assert (s[4].riesgos.fwd_a, s[4].riesgos.fwd_b) == (0b01, 0b01)  # add en EX, x1 de MEM/WB
    assert (s[5].riesgos.flush_if_id, s[5].riesgos.flush_id_ex) == (True, True)  # beq en EX
    assert s[6].pc == 0x10  # IF busca el destino


def test_sin_snapshot_los_latches_estan_vacios() -> None:
    vacios = latches(None)
    assert list(vacios) == list(LATCHES)
    assert not any(latch.valid for latch in vacios.values())


# --- "Qué pasó en este ciclo" --------------------------------------------------------------


def test_explicar_un_ciclo_sin_riesgos() -> None:
    s = snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW))
    assert explicar(s, columnas_pipeline(s, PROGRAMA)) == [
        "Sin riesgos: cada instrucción avanza una etapa."
    ]
    assert [activa for _, activa in senales(s)] == [False] * 5


def test_explicar_load_use() -> None:
    s = snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW), riesgos=RiesgosCiclo(stall=True))
    [frase] = explicar(s, columnas_pipeline(s, PROGRAMA))
    assert frase.startswith("Load-use: «lw x1, 0(x0)» está en EX")
    assert "«add x2, x1, x1» en ID" in frase
    assert senales(s)[0] == ("stall = 1", True)


def test_branch_tomado_destino_y_explicacion() -> None:
    s = snap(0x10, if_id=(0x0C, ADDI3), id_ex=(0x08, BEQ),
             riesgos=RiesgosCiclo(flush_if_id=True, flush_id_ex=True))  # fmt: skip
    s = replace(s, id_ex=replace(s.id_ex, imm=8, branch=True))
    assert destino_salto(s) == 0x10
    [frase] = explicar(s, columnas_pipeline(s, PROGRAMA))
    assert "salta (tomado → 0x10)" in frase
    assert destino_salto(replace(s, id_ex=replace(s.id_ex, jalr=True))) is None


def test_jal_en_id_salta_y_descarta_if() -> None:
    jal = ensamblar("nop\njal x1, f\nnop\nnop\nf: halt\n").palabras[1]  # 0x04 → 0x10
    s = snap(0x08, if_id=(0x04, jal), riesgos=RiesgosCiclo(flush_if_id=True))
    assert destino_salto(s) == 0x10
    [frase] = explicar(s, columnas_pipeline(s, PROGRAMA))
    assert "salta desde ID → 0x10" in frase


def test_explicar_forwarding_marca_el_valor_viejo() -> None:
    s = snap(0x0C, id_ex=(0x08, ADD), ex_mem=(0x04, LW), riesgos=RiesgosCiclo(fwd_a=2, fwd_b=1))
    frases = explicar(s, columnas_pipeline(s, PROGRAMA))
    assert frases[0].startswith("Forwarding A: EX toma el operando de EX/MEM")
    assert "rs1_data de ID/EX es un valor viejo" in frases[0]
    assert frases[1].startswith("Forwarding B: EX toma el operando de MEM/WB")
    assert senales(s)[3:] == [("fwd_a = 10", True), ("fwd_b = 01", True)]
