"""Suite de programas en assembly (US-304): ensambla y corre todo `asm/` en el golden model.

- `tests/instr/` y `tests/hazards/`: terminan con HALT y la firma en 0x3FC vale 1 (AC3, AC4).
- `tests/h2/`: terminan (sin firma; se comparan contra el `.expected` en `make sim-programs`).
- `demos/` y `special/`: terminan como dice cada uno y dejan los resultados de su encabezado.
- AC1: las 33 instrucciones aparecen en `tests/instr/`. AC2: hay un programa por caso de riesgo.
"""

from pathlib import Path

import pytest

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.isa.instrucciones import INSTRUCCIONES, identificar
from riscv_toolkit.iss.golden_model import EstadoArquitectonico, GoldenModel, Motivo

ASM = Path(__file__).resolve().parents[2] / "asm"
DIR_FIRMA = 0x3FC
FIRMA_OK = 1
MAX_INSTR = 100_000

# Casos de la métrica "Cobertura de riesgos" (PRD §1.4)
RIESGOS = {
    "fwd_ex_mem",
    "fwd_mem_wb",
    "fwd_doble",
    "fwd_store_data",
    "fwd_branch",
    "x0_no_forward",
    "load_use",
    "load_use_store",
    "branch_taken",
    "branch_not_taken",
    "branch_after_load",
    "jal_jalr",
    "jal_branch_same_cycle",
    "halt_after_branch",
    "halt_speculative",
    "illegal_speculative",
}


def _programas(*carpetas: str) -> list[Path]:
    return sorted(p for c in carpetas for p in (ASM / c).glob("*.asm"))


def _id(p: Path) -> str:
    return str(p.relative_to(ASM).with_suffix(""))


def _correr(programa: Path) -> tuple[Motivo, GoldenModel]:
    modelo = GoldenModel(ensamblar(programa.read_text()).palabras)
    return modelo.run(MAX_INSTR), modelo


def _estado(programa: Path, motivo_esperado: Motivo = Motivo.HALTED) -> EstadoArquitectonico:
    motivo, modelo = _correr(programa)
    assert motivo is motivo_esperado
    return modelo.estado_final()


def _palabras(estado: EstadoArquitectonico, desde: int, cantidad: int) -> list[int]:
    return [estado.mem_usada[desde + 4 * i] for i in range(cantidad)]


def _sin_signo(*valores: int) -> list[int]:
    return [v & 0xFFFFFFFF for v in valores]


@pytest.mark.parametrize("programa", _programas("tests/instr", "tests/hazards"), ids=_id)
def test_firma(programa: Path) -> None:
    estado = _estado(programa)
    firma = estado.mem_usada.get(DIR_FIRMA, 0)
    assert firma == FIRMA_OK, f"firma = {firma}: falló el caso {firma} (0 = no llegó al final)"


@pytest.mark.parametrize("programa", _programas("tests/h2"), ids=_id)
def test_h2_termina(programa: Path) -> None:
    motivo, _ = _correr(programa)
    assert motivo in {Motivo.HALTED, Motivo.ILLEGAL}


@pytest.mark.parametrize("programa", _programas("tests", "demos", "special"), ids=_id)
def test_encabezado(programa: Path) -> None:
    assert programa.read_text().startswith("# "), "falta el comentario de qué prueba"


@pytest.mark.parametrize("programa", _programas("tests/instr", "tests/hazards"), ids=_id)
def test_firma_solo_al_final(programa: Path) -> None:
    """Ningún programa usa 0x3FC para otra cosa: solo los dos `sw` de la firma la nombran."""
    usos = [linea for linea in programa.read_text().splitlines() if "0X3FC" in linea.upper()]
    assert len(usos) == 2


def test_instr_cubre_las_33_instrucciones() -> None:
    usadas = {
        spec.mnemonico
        for p in _programas("tests/instr")
        for palabra in ensamblar(p.read_text()).palabras
        if (spec := identificar(palabra)) is not None
    }
    assert usadas == set(INSTRUCCIONES)


def test_hay_un_programa_por_riesgo() -> None:
    assert {p.stem for p in _programas("tests/hazards")} >= RIESGOS


def test_demo_suma_arreglo() -> None:
    estado = _estado(ASM / "demos/suma_arreglo.asm")
    assert estado.mem_usada[0x140] == 40


def test_demo_fibonacci() -> None:
    estado = _estado(ASM / "demos/fibonacci.asm")
    fib = [0, 1]
    while len(fib) < 20:
        fib.append(fib[-1] + fib[-2])
    assert _palabras(estado, 0x100, 20) == fib


def test_demo_copia_cadena() -> None:
    estado = _estado(ASM / "demos/copia_cadena.asm")
    assert _palabras(estado, 0x180, 3) == _palabras(estado, 0x100, 3)
    origen = b"".join(v.to_bytes(4, "little") for v in _palabras(estado, 0x100, 3))
    assert origen == b"Hola RISC-V\x00"
    assert estado.regs[12] == len("Hola RISC-V")


def test_demo_burbuja() -> None:
    estado = _estado(ASM / "demos/burbuja.asm")
    assert _palabras(estado, 0x100, 8) == _sin_signo(-9, -2, 0, 1, 3, 3, 7, 15)


def test_demo_subrutina() -> None:
    estado = _estado(ASM / "demos/subrutina.asm")
    assert _palabras(estado, 0x100, 3) == [42, 81, 25]
    assert estado.regs[2] == 0x300  # la pila quedó como estaba


def test_special_no_halt() -> None:
    imagen = ensamblar((ASM / "special/no_halt.asm").read_text())
    assert any("halt" in a for a in imagen.advertencias)
    estado = _estado(ASM / "special/no_halt.asm")
    assert estado.regs[3] == 30


def test_special_infinite_loop() -> None:
    motivo, _ = _correr(ASM / "special/infinite_loop.asm")
    assert motivo is Motivo.TIMEOUT


def test_special_illegal() -> None:
    estado = _estado(ASM / "special/illegal.asm", Motivo.ILLEGAL)
    assert estado.pc == 0x0C
    assert estado.mem_usada == {0x40: 5}
