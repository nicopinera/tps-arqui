"""Verificación cruzada del núcleo contra el golden model (US-305).

Para cada programa de `asm/`: lo ensambla, genera el `.expected` con el golden model, lo corre en
`tb_core_programs` (Icarus, ADR-015) y compara el volcado final del testbench con el golden model:
motivo de terminación, PC, registros, memoria usada, firma (en `tests/instr` y `tests/hazards`) e
instrucciones retiradas. Al final muestra la tabla de ciclos y CPI y la guarda en CSV.

Uso (desde TP3/tools/):
    uv run python -m scripts.verify_rtl                       # toda la suite (make verify)
    uv run python -m scripts.verify_rtl tests/hazards/load_use demos/burbuja

Código de salida: 0 si todos los programas pasan, 1 si alguno falla (AC1).

Los programas que no terminan en el golden model (`special/infinite_loop`) se omiten: no hay un
estado final con el que comparar.

Ciclos y CPI (con enable fijo): `ciclos` va desde el flush global hasta que el núcleo se detiene,
así que incluye el llenado y el vaciado del pipeline (4 ciclos) y el HALT. `CPI = ciclos /
instrucciones`, con las instrucciones retiradas del golden model (sin el HALT). Un programa de N
instrucciones sin riesgos da `N + 5` ciclos.
"""

import argparse
import csv
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.salidas import a_hex
from riscv_toolkit.iss.expected import a_expected
from riscv_toolkit.iss.golden_model import EstadoArquitectonico, GoldenModel, Motivo
from riscv_toolkit.protocol import comandos

TP3 = Path(__file__).resolve().parents[2]
ASM = TP3 / "asm"
BUILD = TP3 / "build" / "verify"
RUTA_CSV = TP3.parent / "docs" / "informe" / "datos" / "cpi.csv"

MAX_INSTR = 100_000  # corte del golden model (un lazo infinito termina con TIMEOUT)
DIR_FIRMA = 0x3FC
FIRMA_OK = 1
CARPETAS_CON_FIRMA = ("tests/instr", "tests/hazards")
SIN_TERMINAR = 0  # motivo del volcado cuando el núcleo no llegó a o_halted
CODIGO_MOTIVO = {
    Motivo.HALTED: comandos.Motivo.HALTED.value,
    Motivo.ILLEGAL: comandos.Motivo.ILLEGAL.value,
}
NOMBRE_MOTIVO = {codigo: m.name for m, codigo in CODIGO_MOTIVO.items()} | {
    SIN_TERMINAR: "NO TERMINÓ"
}
CONTADORES = ("ciclos", "retiradas", "stalls", "flush_if_id", "flush_id_ex")
COLUMNAS_CSV = (
    "programa",
    "resultado",
    "ciclos",
    "instrucciones",
    "cpi",
    "stalls",
    "flush_if_id",
    "flush_id_ex",
)


@dataclass
class Volcado:
    """Estado final del núcleo según las líneas `VOLCADO` de `tb_core_programs`."""

    motivo: int = SIN_TERMINAR
    pc: int = 0
    contadores: dict[str, int] = field(default_factory=dict)
    regs: dict[int, int] = field(default_factory=dict)  # x1 … x31
    mem: dict[int, int] = field(default_factory=dict)  # dirección de byte → dato (solo usadas)


@dataclass
class Resultado:
    programa: str
    ok: bool
    diferencias: list[str]
    instrucciones: int = 0  # del golden model, sin contar el HALT
    volcado: Volcado | None = None

    @property
    def cpi(self) -> float | None:
        if self.volcado is None or self.instrucciones == 0:
            return None
        return self.volcado.contadores["ciclos"] / self.instrucciones


def leer_volcado(texto: str) -> Volcado:
    """Arma el `Volcado` con la salida del testbench. Falla si el volcado está incompleto."""
    lineas = [ln.split()[1:] for ln in texto.splitlines() if ln.startswith("VOLCADO ")]
    if not lineas or lineas[0] != ["inicio"] or lineas[-1] != ["fin"]:
        raise ValueError("el testbench no imprimió un volcado completo (VOLCADO inicio … fin)")
    volcado = Volcado()
    for clave, *valores in lineas[1:-1]:
        if clave == "motivo":
            volcado.motivo = int(valores[0])
        elif clave == "pc":
            volcado.pc = int(valores[0], 16)
        elif clave in CONTADORES:
            volcado.contadores[clave] = int(valores[0])
        elif clave.startswith("x"):
            volcado.regs[int(clave[1:])] = int(valores[0], 16)
        elif clave == "mem":
            volcado.mem[int(valores[0], 16)] = int(valores[1], 16)
        else:
            raise ValueError(f"clave desconocida en el volcado: {clave}")
    faltan = [c for c in CONTADORES if c not in volcado.contadores]
    if faltan or len(volcado.regs) != 31:
        raise ValueError(f"volcado incompleto: faltan {faltan or 'registros'}")
    return volcado


def comparar(
    esperado: EstadoArquitectonico, retiradas: int, volcado: Volcado, con_firma: bool
) -> list[str]:
    """Diferencias entre el golden model y el núcleo, una por línea (AC2). Vacía si coinciden."""
    diferencias = []
    motivo = CODIGO_MOTIVO[esperado.motivo]
    if volcado.motivo != motivo:
        obtenido = NOMBRE_MOTIVO.get(volcado.motivo, str(volcado.motivo))
        diferencias.append(f"motivo: esperado {NOMBRE_MOTIVO[motivo]}, obtenido {obtenido}")
    # El núcleo deja de buscar con el HALT en ID: el PC queda en la instrucción siguiente.
    if volcado.pc != esperado.pc + 4:
        diferencias.append(f"pc: esperado {esperado.pc + 4:#010x}, obtenido {volcado.pc:#010x}")
    for n in range(1, 32):
        if volcado.regs[n] != esperado.regs[n]:
            diferencias.append(
                f"x{n}: esperado {esperado.regs[n]:#010x}, obtenido {volcado.regs[n]:#010x}"
            )
    for direccion in sorted(esperado.mem_usada.keys() | volcado.mem.keys()):
        if direccion not in volcado.mem:
            diferencias.append(
                f"[{direccion:#05x}]: esperado {esperado.mem_usada[direccion]:#010x}, "
                "no está marcada como usada en el núcleo"
            )
        elif direccion not in esperado.mem_usada:
            diferencias.append(
                f"[{direccion:#05x}]: usada en el núcleo ({volcado.mem[direccion]:#010x}) "
                "y no en el golden model"
            )
        elif volcado.mem[direccion] != esperado.mem_usada[direccion]:
            diferencias.append(
                f"[{direccion:#05x}]: esperado {esperado.mem_usada[direccion]:#010x}, "
                f"obtenido {volcado.mem[direccion]:#010x}"
            )
    if con_firma:
        firma = volcado.mem.get(DIR_FIRMA, 0)
        if firma != FIRMA_OK:
            detalle = "no llegó al final" if firma == 0 else f"falló el caso {firma}"
            diferencias.append(f"firma: {firma} ({detalle})")
    # El núcleo también retira el HALT (o la ilegal) en WB; el golden model no lo cuenta.
    if volcado.contadores["retiradas"] != retiradas + 1:
        diferencias.append(
            f"instrucciones retiradas: esperadas {retiradas} + HALT, "
            f"obtenidas {volcado.contadores['retiradas']}"
        )
    return diferencias


def nombre(programa: Path) -> str:
    return str(programa.relative_to(ASM).with_suffix(""))


def verificar(programa: Path) -> Resultado | None:
    """Corre un programa en el golden model y en el núcleo. None si el golden model no termina."""
    imagen = ensamblar(programa.read_text())
    modelo = GoldenModel(imagen.palabras)
    if modelo.run(MAX_INSTR) is Motivo.TIMEOUT:
        return None
    esperado = modelo.estado_final()

    base = BUILD / nombre(programa)
    base.parent.mkdir(parents=True, exist_ok=True)
    hex_, expected, log = (
        base.with_suffix(".hex"),
        base.with_suffix(".expected"),
        base.with_suffix(".log"),
    )
    hex_.write_text(a_hex(imagen))
    expected.write_text(a_expected(esperado))

    entorno = os.environ | {"HEX": str(hex_), "EXPECTED": str(expected), "QUIET": "0"}
    sim = subprocess.run(
        ["bash", "hw/scripts/sim.sh", "tb_core_programs"],  # noqa: S607
        cwd=TP3,
        env=entorno,
        capture_output=True,
        text=True,
        check=False,
    )
    log.write_text(sim.stdout + sim.stderr)
    try:
        volcado = leer_volcado(sim.stdout)
    except ValueError as error:
        return Resultado(nombre(programa), False, [f"{error} (ver {log.relative_to(TP3)})"])

    con_firma = nombre(programa).startswith(CARPETAS_CON_FIRMA)
    diferencias = comparar(esperado, modelo.instrucciones_retiradas, volcado, con_firma)
    if sim.returncode != 0 and not diferencias:
        # El testbench vio algo que el volcado no muestra (por ejemplo, AC3 de US-210)
        diferencias.append(f"el testbench falló (ver {log.relative_to(TP3)})")
    return Resultado(
        nombre(programa), not diferencias, diferencias, modelo.instrucciones_retiradas, volcado
    )


def fila(resultado: Resultado) -> dict[str, str]:
    v = resultado.volcado
    c = v.contadores if v else {}
    cpi = resultado.cpi
    return {
        "programa": resultado.programa,
        "resultado": "OK" if resultado.ok else "FALLA",
        "ciclos": str(c.get("ciclos", "")),
        "instrucciones": str(resultado.instrucciones or ""),
        "cpi": f"{cpi:.3f}" if cpi is not None else "",
        "stalls": str(c.get("stalls", "")),
        "flush_if_id": str(c.get("flush_if_id", "")),
        "flush_id_ex": str(c.get("flush_id_ex", "")),
    }


def imprimir_tabla(resultados: list[Resultado], omitidos: list[str]) -> None:
    ancho = max(len(r.programa) for r in resultados) if resultados else 10
    print(
        f"{'programa':<{ancho}}  resultado  ciclos  instr    CPI  stalls  flush_if_id  flush_id_ex"
    )
    for r in resultados:
        f = fila(r)
        print(
            f"{f['programa']:<{ancho}}  {f['resultado']:<9}  {f['ciclos']:>6}"
            f"  {f['instrucciones']:>5}  {f['cpi']:>5}  {f['stalls']:>6}"
            f"  {f['flush_if_id']:>11}  {f['flush_id_ex']:>11}"
        )
        for diferencia in r.diferencias:
            print(f"{'':<{ancho}}    {diferencia}")
    for programa in omitidos:
        print(f"{programa:<{ancho}}  OMITIDO    no termina en el golden model")


def guardar_csv(resultados: list[Resultado], ruta: Path) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with ruta.open("w", newline="") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=COLUMNAS_CSV, lineterminator="\n")
        escritor.writeheader()
        escritor.writerows(fila(r) for r in resultados)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verificación cruzada núcleo vs. golden model")
    parser.add_argument(
        "programas",
        nargs="*",
        help="programas relativos a asm/, sin .asm (por defecto, todos)",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        help=f"dónde guardar la tabla (por defecto, {RUTA_CSV.relative_to(TP3.parent)} "
        "si se corre toda la suite)",
    )
    args = parser.parse_args(argv)

    if args.programas:
        programas = [ASM / f"{p}.asm" for p in args.programas]
        faltan = [p for p in programas if not p.is_file()]
        if faltan:
            parser.error(f"no existe {faltan[0]}")
    else:
        programas = sorted(ASM.rglob("*.asm"))

    resultados: list[Resultado] = []
    omitidos: list[str] = []
    for programa in programas:
        resultado = verificar(programa)
        if resultado is None:
            omitidos.append(nombre(programa))
        else:
            resultados.append(resultado)

    imprimir_tabla(resultados, omitidos)
    fallas = sum(not r.ok for r in resultados)
    print(
        f"\nVerificación: {len(resultados) - fallas} de {len(resultados)} programas pasaron", end=""
    )
    print(f" ({len(omitidos)} omitidos)" if omitidos else "")

    ruta_csv = args.csv or (None if args.programas else RUTA_CSV)
    if ruta_csv is not None:
        guardar_csv(resultados, ruta_csv)
        mostrada = ruta_csv.resolve().relative_to(TP3.parent, walk_up=True)
        print(f"Tabla de ciclos guardada en {mostrada}")
    return 1 if fallas or not resultados else 0


if __name__ == "__main__":
    sys.exit(main())
