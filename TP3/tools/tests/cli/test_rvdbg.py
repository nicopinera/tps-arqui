"""CLI `rvdbg`, el subcomando `dbg` (US-410), con la placa simulada."""

import argparse
import json
from collections.abc import Iterator
from dataclasses import replace
from pathlib import Path

import pytest

from riscv_toolkit.__main__ import main
from riscv_toolkit.cli import rvdbg
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import ErrorPuerto
from riscv_toolkit.protocol.snapshot import RiesgosCiclo, Snapshot
from riscv_toolkit.protocol.transport import Transport

ASM = Path(__file__).parents[3] / "asm"
FIBONACCI = str(ASM / "demos" / "fibonacci.asm")
INFINITO = str(ASM / "special" / "infinite_loop.asm")
FIXTURES = Path(__file__).parents[1] / "protocol" / "fixtures"

Capsys = pytest.CaptureFixture[str]


def dbg(*argumentos: str) -> int:
    return main(["dbg", "--fake", *argumentos])


class CtrlC(FakeTransport):
    """El fake, pero la primera vez que no hay nada para leer simula un Ctrl+C."""

    armado = True

    def read(self, n: int, timeout: float | None) -> bytes:
        datos = super().read(n, 0)
        if not datos and self.armado:
            self.armado = False
            raise KeyboardInterrupt
        return datos


class Muda:
    """Una placa que no responde nada (AC3)."""

    simulado = False

    def write(self, datos: bytes) -> None:
        pass

    def read(self, n: int, timeout: float | None) -> bytes:
        return b""

    def close(self) -> None:
        pass


def usar(monkeypatch: pytest.MonkeyPatch, transporte: Transport) -> None:
    def abrir(args: argparse.Namespace) -> Transport:
        return transporte

    monkeypatch.setattr(rvdbg, "_abrir", abrir)


# --- AC1: cargar y correr muestra registros y memoria --------------------------------------


def test_run_con_load(capsys: Capsys) -> None:
    assert dbg("run", "--load", FIBONACCI) == 0
    salida = capsys.readouterr().out
    assert "HALTED · motivo HALTED" in salida
    assert "x1  = 0x00000090" in salida  # F(12) = 144
    assert "0x02c: 0x00000059" in salida  # F(11) = 89
    assert "(simulado" in salida


def test_load_solo(capsys: Capsys) -> None:
    assert dbg("load", FIBONACCI) == 0
    assert "12 palabras cargadas" in capsys.readouterr().out


def test_step_muestra_el_avance_y_los_latches(capsys: Capsys) -> None:
    assert dbg("step", "3", "--load", FIBONACCI) == 0
    salida = capsys.readouterr().out
    assert "ciclo     1: pc 0x004" in salida
    assert "STEPPING · 3 ciclos · pc 0x00c" in salida
    assert "IF/ID   0x00c  addi x4, x0, 12" in salida
    assert "MEM/WB  0x000  addi x1, x0, 0" in salida


def test_step_frena_al_terminar(capsys: Capsys, tmp_path: Path) -> None:
    corto = tmp_path / "corto.asm"
    corto.write_text("addi x1, x0, 1\nhalt\n", encoding="utf-8")
    assert dbg("step", "50", "--load", str(corto)) == 0
    salida = capsys.readouterr().out
    assert "HALTED · motivo HALTED · 2 ciclos" in salida
    assert salida.count(": pc 0x") == 1  # el avance del primer STEP; el segundo es el resumen


def test_dump_ping_y_reset(capsys: Capsys) -> None:
    assert dbg("dump") == 0
    assert "IDLE · 0 ciclos" in capsys.readouterr().out
    assert dbg("ping") == 0
    assert "protocolo v1" in capsys.readouterr().out
    assert dbg("reset") == 0
    assert "RESET" in capsys.readouterr().out


def test_dump_mem(capsys: Capsys) -> None:
    assert dbg("dump-mem", "0x8", "2") == 0
    assert capsys.readouterr().out == "0x008: 0x00000000\n0x00c: 0x00000000\n"


# --- AC2: NACK legible ---------------------------------------------------------------------


def test_run_sin_programa(capsys: Capsys) -> None:
    assert dbg("run") == 1
    salida = capsys.readouterr()
    assert salida.out == ""
    assert salida.err == (
        "error: No se puede ejecutar RUN: no hay un programa cargado. Cargá uno con load.\n"
    )


def test_abort_sin_ejecucion(capsys: Capsys) -> None:
    assert dbg("abort") == 1
    assert "no hay una ejecución en curso" in capsys.readouterr().err


def test_dump_mem_fuera_de_rango(capsys: Capsys) -> None:
    assert dbg("dump-mem", "2", "1") == 1
    assert "no está alineada a 4" in capsys.readouterr().err


def test_errores_del_archivo(capsys: Capsys, tmp_path: Path) -> None:
    malo = tmp_path / "malo.asm"
    malo.write_text("addi x1, x0, 1\nfoo x1\n", encoding="utf-8")
    assert dbg("load", str(malo)) == 1
    assert f"{malo}:2: " in capsys.readouterr().err
    assert dbg("load", str(tmp_path / "no_existe.asm")) == 1
    assert "no se pudo leer" in capsys.readouterr().err


def test_advertencias_a_stderr(capsys: Capsys, tmp_path: Path) -> None:
    sin_halt = tmp_path / "sin_halt.asm"
    sin_halt.write_text("addi x1, x0, 1\n", encoding="utf-8")
    assert dbg("load", str(sin_halt)) == 0
    assert "advertencia" in capsys.readouterr().err


def test_step_rechaza_n_cero(capsys: Capsys) -> None:
    with pytest.raises(SystemExit):
        dbg("step", "0")
    assert "al menos 1" in capsys.readouterr().err


# --- AC3: la placa no responde -------------------------------------------------------------


def test_placa_muda(capsys: Capsys, monkeypatch: pytest.MonkeyPatch) -> None:
    usar(monkeypatch, Muda())
    assert main(["dbg", "ping"]) == 1
    assert "no respondió a 3 PING" in capsys.readouterr().err


def test_sin_placa_conectada(capsys: Capsys, monkeypatch: pytest.MonkeyPatch) -> None:
    def sin_placa(puerto: str | None) -> Transport:
        raise ErrorPuerto("no se encontró la Basys 3")

    monkeypatch.setattr(rvdbg, "SerialTransport", sin_placa)
    assert main(["dbg", "--json", "ping"]) == 1
    assert json.loads(capsys.readouterr().out) == {
        "ok": False,
        "error": "no se encontró la Basys 3",
    }


# --- AC4: --json ---------------------------------------------------------------------------


def test_json_de_run(capsys: Capsys) -> None:
    assert dbg("--json", "run", "--load", FIBONACCI) == 0
    datos = json.loads(capsys.readouterr().out)
    assert datos["ok"] is True
    assert datos["estado"] == "HALTED"
    assert datos["motivo"] == "HALTED"
    assert datos["regs"][2] == 233
    assert datos["mem_usada"][11] == {"addr": 0x2C, "dato": 89}
    assert datos["if_id"]["valid"] is False
    assert datos["simulado"] is True


def test_json_de_error_y_dump_mem(capsys: Capsys) -> None:
    assert dbg("--json", "step") == 1
    assert json.loads(capsys.readouterr().out)["ok"] is False
    assert dbg("--json", "dump-mem", "0", "2") == 0
    assert json.loads(capsys.readouterr().out) == {"ok": True, "addr": 0, "palabras": [0, 0]}


# --- AC5: Ctrl+C durante run manda ABORT ---------------------------------------------------


def test_ctrl_c_durante_run(capsys: Capsys, monkeypatch: pytest.MonkeyPatch) -> None:
    usar(monkeypatch, CtrlC())
    assert main(["dbg", "run", "--load", INFINITO]) == 0
    salida = capsys.readouterr()
    assert "Ctrl+C: mandando ABORT" in salida.err
    assert "HALTED · motivo ABORTED" in salida.out


def test_ctrl_c_en_otra_accion(capsys: Capsys, monkeypatch: pytest.MonkeyPatch) -> None:
    class Interrumpe(Muda):
        def read(self, n: int, timeout: float | None) -> bytes:
            raise KeyboardInterrupt

    usar(monkeypatch, Interrumpe())
    assert main(["dbg", "dump"]) == 1  # el Ctrl+C llega esperando el PING de conectar
    assert "interrumpido" in capsys.readouterr().err


def test_formato_de_riesgos() -> None:
    snap = Snapshot.from_bytes((FIXTURES / "snapshot_sim.bin").read_bytes())
    snap = replace(snap, riesgos=RiesgosCiclo(stall=True, flush_id_ex=True, fwd_a=2, fwd_b=1))
    texto = rvdbg.formatear_snapshot(snap)
    assert "riesgos: stall, flush ID/EX, fwd A=EX/MEM, fwd B=MEM/WB" in texto


# --- shell ---------------------------------------------------------------------------------


def renglones(monkeypatch: pytest.MonkeyPatch, *entrada: str) -> None:
    pendientes: Iterator[str] = iter(entrada)

    def leer(prompt: str) -> str:
        try:
            return next(pendientes)
        except StopIteration:
            raise EOFError from None

    monkeypatch.setattr("builtins.input", leer)


def test_shell_mantiene_la_sesion(capsys: Capsys, monkeypatch: pytest.MonkeyPatch) -> None:
    renglones(monkeypatch, f"load {FIBONACCI}", "", "step", "run", "step", "dump-mem 0x2c 1",
              "accion_inventada", 'load "sin cerrar', "salir", "dump")  # fmt: skip
    assert dbg("shell") == 0
    salida = capsys.readouterr()
    assert "12 palabras cargadas" in salida.out
    assert "STEPPING · 1 ciclos" in salida.out
    assert "HALTED · motivo HALTED" in salida.out
    assert "el procesador está detenido (HALTED)" in salida.err  # el step después del run
    assert "0x02c: 0x00000059" in salida.out
    assert "invalid choice" in salida.err  # argparse
    assert "IDLE" not in salida.out  # después de salir no corrió el dump


def test_shell_termina_con_fin_de_entrada(capsys: Capsys, monkeypatch: pytest.MonkeyPatch) -> None:
    renglones(monkeypatch, "ping")
    assert dbg("--json", "shell") == 0
    assert '{"ok": true, "version": 1}' in capsys.readouterr().out
