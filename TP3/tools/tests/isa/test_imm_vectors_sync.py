"""Los vectores versionados de `tb_imm_gen.v` coinciden con lo que genera el script (US-203)."""

from scripts.gen_imm_vectors import RUTA_ESPERADO, RUTA_HEX, generar


def test_vectores_imm_gen_al_dia() -> None:
    contenido_hex, contenido_esperado = generar()
    mensaje = (
        "vectores de imm_gen desactualizados: correr `uv run python -m scripts.gen_imm_vectors`"
    )
    assert RUTA_HEX.read_text("ascii") == contenido_hex, mensaje
    assert RUTA_ESPERADO.read_text("ascii") == contenido_esperado, mensaje


def test_al_menos_50_vectores_y_los_cinco_formatos() -> None:
    _, contenido_esperado = generar()
    vectores = [linea for linea in contenido_esperado.splitlines() if not linea.startswith("//")]
    assert len(vectores) >= 50  # US-203 AC2
    assert {linea[0] for linea in vectores} == {"0", "1", "2", "3", "4"}


def test_extremos_de_cada_formato() -> None:
    _, contenido_esperado = generar()
    for esperado in (
        "0_fffff800",  # I: -2048
        "0_000007ff",  # I: 2047
        "1_fffff800",  # S: -2048
        "3_80000000",  # U: bit 31 en 1
        "2_fffff000",  # B: -4096
        "2_00000ffe",  # B: 4094
        "4_fff00000",  # J: -1048576
        "4_000ffffe",  # J: 1048574
    ):
        assert esperado in contenido_esperado
