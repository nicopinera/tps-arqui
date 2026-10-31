"""El `du_defs.vh` versionado coincide con lo que genera `comandos.py` (US-104)."""

from scripts.gen_du_defs import RUTA_VH, generar_vh


def test_du_defs_vh_esta_al_dia() -> None:
    assert RUTA_VH.read_text("ascii") == generar_vh(), (
        "du_defs.vh desactualizado: correr `uv run python -m scripts.gen_du_defs` desde tools/"
    )


def test_literales_con_ancho() -> None:
    vh = generar_vh()
    assert "`define DU_CMD_LOAD 8'h4C\n" in vh
    assert "`define DU_ESTADO_HALTED 4'h6\n" in vh
    assert "`define DU_HALT_WORD 32'h0000000B\n" in vh
    assert "`define DU_HALT_OPCODE 7'h0B\n" in vh
    assert "`define DU_IMEM_DEPTH 256\n" in vh
