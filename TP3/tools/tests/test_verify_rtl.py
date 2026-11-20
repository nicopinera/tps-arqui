"""Parser del volcado de `tb_core_programs` y comparación con el golden model (US-305).

No corren el simulador: la corrida completa es `make verify`.
"""

import pytest

from riscv_toolkit.iss.golden_model import EstadoArquitectonico, Motivo
from scripts.verify_rtl import Resultado, Volcado, comparar, fila, leer_volcado

REGS = (0, 5, 0xFFFFFFFF) + (0,) * 29
ESPERADO = EstadoArquitectonico(
    regs=REGS, mem_usada={0x100: 7, 0x3FC: 1}, pc=0x10, motivo=Motivo.HALTED
)
RETIRADAS = 4


def _texto(**cambios: str) -> str:
    """Volcado como lo imprime el testbench, coincidente con ESPERADO salvo `cambios`."""
    datos = {
        "motivo": "1",
        "pc": "00000014",
        "ciclos": "12",
        "retiradas": "5",
        "stalls": "1",
        "flush_if_id": "0",
        "flush_id_ex": "0",
    }
    datos |= {f"x{n}": f"{REGS[n]:08x}" for n in range(1, 32)}
    datos |= cambios
    lineas = ["Programa: x.hex", "VOLCADO inicio"]
    lineas += [f"VOLCADO {clave} {valor}" for clave, valor in datos.items()]
    lineas += ["VOLCADO mem 00000100 00000007", "VOLCADO mem 000003fc 00000001", "VOLCADO fin"]
    return "\n".join(lineas) + "\nTEST PASSED\n"


def test_leer_volcado() -> None:
    v = leer_volcado(_texto())
    assert v.motivo == 1
    assert v.pc == 0x14
    assert v.contadores == {
        "ciclos": 12,
        "retiradas": 5,
        "stalls": 1,
        "flush_if_id": 0,
        "flush_id_ex": 0,
    }
    assert v.regs[2] == 0xFFFFFFFF
    assert v.mem == {0x100: 7, 0x3FC: 1}


@pytest.mark.parametrize(
    "texto",
    ["sin volcado\nTEST FAILED\n", "VOLCADO inicio\nVOLCADO motivo 1\n"],
    ids=["sin_volcado", "sin_fin"],
)
def test_volcado_incompleto(texto: str) -> None:
    with pytest.raises(ValueError, match="volcado"):
        leer_volcado(texto)


def test_volcado_sin_contadores() -> None:
    texto = "\n".join(ln for ln in _texto().splitlines() if "stalls" not in ln)
    with pytest.raises(ValueError, match="stalls"):
        leer_volcado(texto)


def test_volcado_clave_desconocida() -> None:
    with pytest.raises(ValueError, match="desconocida"):
        leer_volcado(_texto(otra="1"))


def test_coincide() -> None:
    assert comparar(ESPERADO, RETIRADAS, leer_volcado(_texto()), con_firma=True) == []


def test_diferencias() -> None:
    volcado = leer_volcado(_texto(motivo="2", pc="00000018", x1="00000006", retiradas="7"))
    volcado.mem[0x100] = 8  # dato distinto
    volcado.mem[0x200] = 1  # usada de más
    del volcado.mem[0x3FC]  # sin firma
    diferencias = comparar(ESPERADO, RETIRADAS, volcado, con_firma=True)
    assert diferencias == [
        "motivo: esperado HALTED, obtenido ILLEGAL",
        "pc: esperado 0x00000014, obtenido 0x00000018",
        "x1: esperado 0x00000005, obtenido 0x00000006",
        "[0x100]: esperado 0x00000007, obtenido 0x00000008",
        "[0x200]: usada en el núcleo (0x00000001) y no en el golden model",
        "[0x3fc]: esperado 0x00000001, no está marcada como usada en el núcleo",
        "firma: 0 (no llegó al final)",
        "instrucciones retiradas: esperadas 4 + HALT, obtenidas 7",
    ]


def test_firma_con_caso_fallido() -> None:
    esperado = EstadoArquitectonico(REGS, {0x100: 7, 0x3FC: 3}, 0x10, Motivo.HALTED)
    volcado = leer_volcado(_texto())
    volcado.mem[0x3FC] = 3
    assert comparar(esperado, RETIRADAS, volcado, con_firma=True) == ["firma: 3 (falló el caso 3)"]
    assert comparar(esperado, RETIRADAS, volcado, con_firma=False) == []


def test_no_termino() -> None:
    volcado = leer_volcado(_texto(motivo="0"))
    assert comparar(ESPERADO, RETIRADAS, volcado, con_firma=False) == [
        "motivo: esperado HALTED, obtenido NO TERMINÓ"
    ]


def test_fila_y_cpi() -> None:
    resultado = Resultado("tests/x", True, [], instrucciones=8, volcado=leer_volcado(_texto()))
    assert resultado.cpi == 1.5
    assert fila(resultado) == {
        "programa": "tests/x",
        "resultado": "OK",
        "ciclos": "12",
        "instrucciones": "8",
        "cpi": "1.500",
        "stalls": "1",
        "flush_if_id": "0",
        "flush_id_ex": "0",
    }


def test_fila_sin_volcado() -> None:
    resultado = Resultado("tests/x", False, ["el testbench no imprimió un volcado"])
    assert resultado.cpi is None
    assert fila(resultado)["resultado"] == "FALLA"
    assert fila(resultado)["ciclos"] == ""


def test_volcado_por_defecto() -> None:
    assert Volcado().motivo == 0
