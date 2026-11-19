"""Lo que sale de recorrer el historial: quién escribió qué, la tabla y el resumen."""

from dataclasses import fields, replace

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.snapshot import LatchEXMEM, LatchMEMWB, RiesgosCiclo, Snapshot
from riscv_toolkit.session.debug_session import DebugSession
from riscv_toolkit.ui.historial import (
    cambios_registros,
    escribe_al_final,
    eventos,
    filas_historial,
    origen_de,
    resumen,
    ultimas_escrituras,
    valor_wb,
)
from riscv_toolkit.ui.latch_info import CAMPOS
from riscv_toolkit.ui.pipeline import latches
from tests.ui.test_pipeline import ADD, LW, PROGRAMA, VACIO, snap

SW = ensamblar("sw x1, 4(x0)\n").palabras[0]


def test_eventos() -> None:
    r = RiesgosCiclo(stall=True, flush_id_ex=True, fwd_b=1)
    assert eventos(replace(VACIO, riesgos=r)) == ("st", "fl", "fb")
    assert eventos(VACIO) == ()


def test_valor_wb_segun_result_src() -> None:
    wb = LatchMEMWB(alu_result=1, mem_data=2, pc_plus4=3)
    assert [valor_wb(replace(wb, result_src=s)) for s in (0, 1, 2)] == [1, 2, 3]


def test_quien_escribio_un_registro_y_la_memoria() -> None:
    # Ciclo 7: add en WB escribe x2; sw en MEM escribe [0x4]. Ciclo 8: ya están escritos.
    a = replace(
        snap(0x10, ex_mem=(0x08, SW), mem_wb=(0x04, ADD)),
        ciclos=7,
        mem_wb=LatchMEMWB(pc_plus4=0x08, instr=ADD, valid=True, reg_write=True, rd=2,
                          alu_result=10),
        ex_mem=LatchEXMEM(pc_plus4=0x0C, instr=SW, valid=True, mem_write=True),
    )  # fmt: skip
    b = replace(VACIO, ciclos=8, regs=(0, 0, 10, *(0,) * 29), mem_usada={4: 5})
    assert escribe_al_final(a) == (2, 10, "add x2, x1, x1")
    assert escribe_al_final(b) is None
    [cambio] = cambios_registros(a, b)
    assert (cambio.reg, cambio.antes, cambio.despues, cambio.quien, cambio.ciclo) == (
        2, 0, 10, "add x2, x1, x1", 7,
    )  # fmt: skip
    assert ultimas_escrituras([a, b]) == {4: "sw x1, 4(x0) · ciclo 7"}
    assert origen_de([a, b], "x2") == (0, "add x2, x1, x1")
    assert origen_de([a, b], "[0x004]") == (0, "sw x1, 4(x0)")
    assert origen_de([a, b], "x3") is None


def test_despues_de_un_run_no_se_sabe_quien() -> None:
    a = replace(VACIO, ciclos=0)
    b = replace(VACIO, ciclos=50, regs=(0, 1, *(0,) * 30), mem_usada={0: 1})
    [cambio] = cambios_registros(a, b)
    assert cambio.quien is None
    assert ultimas_escrituras([a, b]) == {0: "durante un RUN"}
    assert origen_de([a, b], "x1") is None


def test_no_culpa_a_una_instruccion_que_no_escribe() -> None:
    # Ciclos seguidos, pero en WB hay un sw (no escribe registros) y en MEM no hay un store.
    a = replace(snap(0x10, ex_mem=(0x08, ADD), mem_wb=(0x04, SW)), ciclos=3)
    b = replace(VACIO, ciclos=4, regs=(0, 1, *(0,) * 30), mem_usada={0: 1})
    assert cambios_registros(a, b)[0].quien is None
    assert ultimas_escrituras([a, b]) == {0: "—"}
    assert origen_de([a, b], "x1") is None
    assert origen_de([a, b], "[0x000]") is None


def test_filas_historial() -> None:
    a = replace(snap(0x04, if_id=(0x00, LW)), ciclos=1)
    b = replace(snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW)), ciclos=2,
                riesgos=RiesgosCiclo(stall=True), regs=(0, 7, *(0,) * 30))  # fmt: skip
    filas = filas_historial([a, b], PROGRAMA)
    assert filas[0].etapas == ("add", "lw", "—", "—", "—")
    assert filas[1].etapas == ("beq", "add", "lw", "—", "—")
    assert filas[1].eventos == ("st",)
    assert (filas[0].cambios, filas[1].cambios) == ("", "x1 ← 0x7")


def test_resumen_de_una_corrida_paso_a_paso() -> None:
    with DebugSession(FakeTransport()) as sesion:
        sesion.load(ensamblar("addi x1, x0, 1\nsw x1, 0(x0)\nlw x2, 0(x0)\nhalt\n").palabras)
        sesion.dump()
        while sesion.step().motivo is None:
            pass
        snaps = list(sesion.historial)
    r = resumen(snaps, None)
    assert r.completo
    assert r.ciclos == snaps[-1].ciclos
    assert len(r.ocupadas) == len(snaps)
    assert sum(r.reparto.values()) == r.ciclos
    assert r.reparto["Útiles"] == r.instrucciones
    if r.instrucciones:  # el fake no simula el pipeline: solo que las cuentas cierran
        assert r.cpi == r.ciclos / r.instrucciones


def test_resumen_cuenta_riesgos_y_la_mezcla() -> None:
    def retirada(instr: int, ciclo: int, **riesgos: bool | int) -> Snapshot:
        return replace(
            VACIO, ciclos=ciclo, riesgos=RiesgosCiclo(**riesgos),  # type: ignore[arg-type]
            mem_wb=LatchMEMWB(instr=instr, valid=True),
        )  # fmt: skip

    snaps = [retirada(LW, 1, stall=True), retirada(ADD, 2, fwd_a=2, fwd_b=1),
             retirada(ADD, 3, flush_if_id=True, flush_id_ex=True)]  # fmt: skip
    r = resumen(snaps, PROGRAMA)
    assert (r.instrucciones, r.stalls, r.flushes, r.forwardings) == (3, 1, 2, 2)
    assert r.mezcla == {"ALU registro": 2, "Load": 1}
    assert r.reparto == {"Útiles": 3, "Llenar y vaciar": 0, "Stall": 1, "Flush": 2}


def test_resumen_con_un_run_no_es_completo() -> None:
    r = resumen([replace(VACIO, ciclos=0), replace(VACIO, ciclos=40)], None)
    assert not r.completo


def test_cada_latch_tiene_explicados_todos_sus_campos_en_orden() -> None:
    # Si el protocolo suma un campo, la página Campos lo tiene que explicar.
    for nombre, latch in latches(None).items():
        assert [c.nombre for c in CAMPOS[nombre]] == [f.name for f in fields(latch)], nombre
