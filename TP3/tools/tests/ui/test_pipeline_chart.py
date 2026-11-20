"""Carta de pipeline desde un historial sintético (US-503)."""

from dataclasses import replace

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.snapshot import RiesgosCiclo, Snapshot
from riscv_toolkit.session.debug_session import DebugSession
from riscv_toolkit.ui.pipeline_chart import Carta, carta_pipeline
from tests.ui.test_pipeline import ADD, ADDI3, ADDI4, BEQ, LW, PROGRAMA, snap
from tests.ui.test_pipeline import HALT as HALT_W

STALL = RiesgosCiclo(stall=True)
SALTO = RiesgosCiclo(flush_if_id=True, flush_id_ex=True)


def dibujo(carta: Carta) -> list[str]:
    """Cada fila como texto: `lw x1, 0(x0) | IF ID EX* ...` (`*` stall, `~` flush, `.` vacío)."""
    lineas = []
    for f in carta.filas:
        celdas = []
        for t in range(len(carta.ciclos)):
            c = f.celdas.get(t)
            marca = "" if c is None else "*" if c.congelada else "~" if c.anulada else ""
            celdas.append("." if c is None else c.etapa + marca)
        lineas.append(f"{f.texto} | {' '.join(celdas)}")
    return lineas


def numerados(*snaps: Snapshot) -> list[Snapshot]:
    """Los snapshots como ciclos seguidos 0, 1, 2… (`snap` los deja todos en 0)."""
    return [replace(s, ciclos=i) for i, s in enumerate(snaps)]


def test_sin_riesgos_cada_instruccion_baja_en_diagonal() -> None:
    hist = numerados(
        snap(0x00),
        snap(0x04, if_id=(0x00, LW)),
        snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW)),
    )
    carta = carta_pipeline(hist, PROGRAMA)
    assert carta.completa
    assert carta.ciclos == [0, 1, 2]
    assert dibujo(carta) == [
        "lw x1, 0(x0) | IF ID EX",
        "add x2, x1, x1 | . IF ID",
        "beq x0, x0, 0x10 | . . IF",
    ]


def test_ac1_load_use_burbuja_y_id_repetido() -> None:
    hist = numerados(
        snap(0x00),
        snap(0x04, if_id=(0x00, LW)),
        snap(0x08, if_id=(0x04, ADD), id_ex=(0x00, LW), riesgos=STALL),  # add depende de lw
        snap(0x08, if_id=(0x04, ADD), ex_mem=(0x00, LW)),  # burbuja en EX, add sigue en ID
        snap(0x0C, if_id=(0x08, BEQ), id_ex=(0x04, ADD), mem_wb=(0x00, LW)),
    )
    assert dibujo(carta_pipeline(hist, PROGRAMA)) == [
        "lw x1, 0(x0) | IF ID EX MEM WB",
        "add x2, x1, x1 | . IF ID* ID EX",
        "beq x0, x0, 0x10 | . . IF* IF ID",
        "burbuja | . . . EX MEM",
        "addi x3, x0, 3 | . . . . IF",
    ]


def test_ac2_branch_tomado_anula_dos_y_sigue_en_el_destino() -> None:
    hist = numerados(
        snap(0x0C, if_id=(0x08, BEQ)),
        snap(0x10, if_id=(0x0C, ADDI3), id_ex=(0x08, BEQ), riesgos=SALTO),  # beq tomado en EX
        snap(0x10, ex_mem=(0x08, BEQ)),  # los dos de atrás se descartaron; IF = destino
        snap(0x14, if_id=(0x10, ADDI4), mem_wb=(0x08, BEQ)),
    )
    assert dibujo(carta_pipeline(hist, PROGRAMA)) == [
        "beq x0, x0, 0x10 | ID EX MEM WB",
        "addi x3, x0, 3 | IF ID~ . .",
        "addi x4, x0, 4 | . IF~ . .",  # el que estaba en IF al saltar (0x10, por casualidad)
        "addi x4, x0, 4 | . . IF ID",  # el destino: otra instancia
        "halt | . . . IF",
    ]


def test_ac3_un_loop_da_una_fila_por_vuelta() -> None:
    programa = ensamblar("loop: addi x1, x1, 1\nj loop\n").palabras
    sesion = DebugSession(FakeTransport())
    sesion.load(programa)
    sesion.dump()
    for _ in range(9):  # cada vuelta son 3 ciclos: addi, j y la burbuja del flush del j
        sesion.step()
    carta = carta_pipeline(sesion.historial, programa)
    textos = [f.texto for f in carta.filas]
    assert textos.count("addi x1, x1, 1") == 4  # vuelta 1 … 4 (la cuarta, recién en IF)
    assert all(len(f.celdas) <= 5 for f in carta.filas)  # nadie se pega con otra vuelta


def test_un_run_corta_la_carta() -> None:
    hist = [snap(0x00), replace(snap(0x04, if_id=(0x00, LW)), ciclos=40)]
    carta = carta_pipeline(hist, PROGRAMA)
    assert not carta.completa
    assert carta.ciclos == [0, 40]
    assert dibujo(carta) == [
        "lw x1, 0(x0) | IF .",
        "lw x1, 0(x0) | . ID",  # después del salto, otra fila
        "add x2, x1, x1 | . IF",
    ]


def test_pc_que_no_coincide_arranca_otra_fila() -> None:
    hist = numerados(snap(0x00), snap(0x08, if_id=(0x04, ADD)))
    assert len(carta_pipeline(hist, PROGRAMA).filas) == 3  # lw (IF), add (ID), beq (IF)


def test_historial_vacio() -> None:
    assert carta_pipeline([], PROGRAMA) == Carta([], [], True)


def test_forwarding_en_ex_y_fila_de_halt() -> None:
    hist = numerados(
        snap(0x0C, id_ex=(0x08, ADD), riesgos=RiesgosCiclo(fwd_a=2, fwd_b=1)),
        snap(0x18, if_id=(0x14, HALT_W), ex_mem=(0x08, ADD)),
    )
    carta = carta_pipeline(hist, PROGRAMA)
    add = next(f for f in carta.filas if f.texto.startswith("add"))
    assert add.celdas[0].fwd == "AB"
    assert add.celdas[1].fwd == ""
    assert next(f for f in carta.filas if f.texto == "halt").halt
    assert not add.anulada
