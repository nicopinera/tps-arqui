"""verify_board.py contra FakeTransport, sin placa (US-411)."""

from dataclasses import replace
from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.iss.golden_model import GoldenModel
from riscv_toolkit.protocol.comandos import EstadoDU, Motivo
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import ErrorPuerto
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.protocol.transport import Transport
from riscv_toolkit.session.debug_session import DebugSession, Timeouts
from scripts import verify_board
from scripts.verify_board import (
    FALLA,
    OMITIDO,
    PASA,
    comparar,
    comparar_step_run,
    main,
    verificar_programa,
)

ISS = Path(__file__).parents[1] / "iss" / "fixtures"
ASM = Path(__file__).parents[3] / "asm"
FIBONACCI = ASM / "demos" / "fibonacci.asm"


def correr_fake(archivo: Path) -> Snapshot:
    with DebugSession(FakeTransport()) as sesion:
        sesion.load(ensamblar(archivo.read_text(encoding="utf-8")).palabras)
        return sesion.run()


def golden(archivo: Path) -> GoldenModel:
    modelo = GoldenModel(ensamblar(archivo.read_text(encoding="utf-8")).palabras)
    modelo.run(10_000)
    return modelo


def test_suite_completa_con_step(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    reporte = tmp_path / "datos" / "resultados_placa.md"
    bit = tmp_path / "top.bit"
    bit.write_bytes(b"bitstream")
    rutas = [str(ISS), str(ASM)]
    assert (
        main([*rutas, "--fake", "--step", "--reporte", str(reporte), "--bitstream", str(bit)]) == 0
    )

    texto = reporte.read_text(encoding="utf-8")
    assert "| fibonacci.asm | RUN | PASA |" in texto
    assert "| fibonacci.asm | STEP | PASA |" in texto
    assert "| infinite_loop.asm | RUN | OMITIDO |" in texto
    assert "(North Star, AC1):** 5 de 5 (100.0 %)" in texto
    assert "sha256 `" in texto
    assert "FakeTransport" in texto
    assert "PASA    loop.asm (STEP)" in capsys.readouterr().out


def test_comparar_igual_y_distinto() -> None:
    snap = correr_fake(FIBONACCI)
    esperado = golden(FIBONACCI).estado_final()
    assert comparar(snap, esperado) == []

    roto = replace(snap, motivo=Motivo.ILLEGAL, regs=(0, 1, *snap.regs[2:]),
                   mem_usada={**snap.mem_usada, 0x100: 0})  # fmt: skip
    assert comparar(roto, esperado) == [
        "motivo ILLEGAL (esperado HALTED)",
        "x1 = 0x00000001 (esperado 0x00000090)",
        "[0x100] = 0x00000000 (esperado no escrita)",
    ]


def test_comparar_step_run() -> None:
    snap = correr_fake(FIBONACCI)
    assert comparar_step_run(snap, snap) == []
    otro = replace(snap, motivo=None, regs=(0, 1, *snap.regs[2:]), mem_usada={0x0: 5})
    assert comparar_step_run(otro, snap) == [
        "motivo ninguno (RUN: HALTED)",
        "x1 = 0x00000001 (RUN: 0x00000090)",
        "[0x000] = 0x00000005 (RUN: 0x00000000)",
        *(f"[0x{d:03x}] = 0x00000000 (RUN: 0x{v:08x})" for d, v in snap.mem_usada.items() if v),
    ]


def test_run_colgado_falla_y_aborta() -> None:
    sesion = DebugSession(FakeTransport(max_instr=5), Timeouts(run=0.05, sondeo=0.01))
    [resultado] = verificar_programa(sesion, ISS / "loop.asm", con_step=False)
    assert resultado.resultado == FALLA
    assert "se mandó ABORT" in resultado.detalle
    assert sesion.dump().motivo is Motivo.ABORTED  # la placa quedó lista para el próximo


def test_programa_que_no_ensambla(tmp_path: Path) -> None:
    malo = tmp_path / "malo.asm"
    malo.write_text("foo\n", encoding="utf-8")
    [resultado] = verificar_programa(DebugSession(FakeTransport()), malo, con_step=True)
    assert resultado.resultado == FALLA
    assert resultado.detalle.startswith("no ensambla")


def test_un_error_de_la_sesion_es_una_falla_del_programa() -> None:
    sesion = DebugSession(FakeTransport())
    sesion.estado = EstadoDU.RUN  # LOAD se rechaza sin mandarlo
    [resultado] = verificar_programa(sesion, FIBONACCI, con_step=False)
    assert resultado.resultado == FALLA
    assert "No se puede ejecutar LOAD" in resultado.detalle


def test_pasa() -> None:
    [resultado] = verificar_programa(DebugSession(FakeTransport()), FIBONACCI, con_step=False)
    assert resultado.resultado == PASA
    assert resultado.ciclos == 89


def test_omitidos_no_cuentan(tmp_path: Path) -> None:
    infinito = ASM / "special" / "infinite_loop.asm"
    [resultado] = verificar_programa(DebugSession(FakeTransport()), infinito, con_step=False)
    assert resultado.resultado == OMITIDO


def test_errores_de_uso(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main([str(tmp_path), "--fake"]) == 1
    assert "no hay programas" in capsys.readouterr().err
    assert main([str(FIBONACCI), "--fake", "--bitstream", str(tmp_path / "no.bit")]) == 1
    assert "no existe el bitstream" in capsys.readouterr().err


def test_sin_placa(capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch) -> None:
    def sin_placa(puerto: str | None) -> Transport:
        raise ErrorPuerto("no se encontró la Basys 3")

    monkeypatch.setattr(verify_board, "SerialTransport", sin_placa)
    assert main([str(FIBONACCI)]) == 1
    assert "no se encontró la Basys 3" in capsys.readouterr().err


def test_una_falla_sale_con_1(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(verify_board, "comparar", lambda snap, esperado: ["x1 distinto"])
    assert main([str(FIBONACCI), "--fake"]) == 1
