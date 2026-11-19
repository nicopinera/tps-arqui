"""Validación de extremo a extremo en la placa (US-411).

Para cada programa: ensambla → LOAD → RUN → compara el snapshot final contra el golden model
(registros, memoria usada y motivo de terminación). Con `--step` además lo vuelve a cargar, lo
corre ciclo a ciclo con STEP hasta que termina y compara contra el resultado de RUN (AC2).

Los programas se cargan uno detrás de otro **sin RESET**: la corrida de la suite es también la
prueba de reprogramación (AC3, hacen falta al menos 5 programas). El PC final no se compara:
en la placa queda congelado unos ciclos después del HALT, y en el golden model en el HALT.

Uso (desde TP3/tools/, con la placa programada con el bitstream del núcleo):

    uv run python -m scripts.verify_board                          # toda TP3/asm/
    uv run python -m scripts.verify_board ../asm/demos --step
    uv run python -m scripts.verify_board --bitstream ../build/top.bit \\
        --reporte ../../docs/informe/datos/resultados_placa.md
    uv run python -m scripts.verify_board --fake                   # sin placa: FakeTransport

Los programas que en el golden model no terminan (`special/infinite_loop.asm`) se omiten.
Sale con 0 si todos los programas verificados pasan y con 1 si no.
"""

import argparse
import hashlib
import subprocess
import sys
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.iss.golden_model import GoldenModel
from riscv_toolkit.iss.golden_model import Motivo as MotivoISS
from riscv_toolkit.protocol.codec import ErrorTrama
from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import ErrorPuerto, SerialTransport
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.protocol.transport import Transport
from riscv_toolkit.session.debug_session import DebugSession, ErrorSesion, Timeouts
from riscv_toolkit.session.diff import diff
from riscv_toolkit.session.verificar import MAX_INSTR, comparar, nombre_motivo

SUITE = Path(__file__).resolve().parents[2] / "asm"  # TP3/asm/
_TIMEOUT_RUN_S = 10.0  # un programa de la suite termina en microsegundos; más es un cuelgue

PASA, FALLA, OMITIDO = "PASA", "FALLA", "OMITIDO"


@dataclass(frozen=True)
class Resultado:
    """Una fila del reporte: un programa en un modo."""

    programa: str
    modo: str  # "RUN" o "STEP"
    resultado: str  # PASA, FALLA u OMITIDO
    ciclos: int | None = None
    detalle: str = ""


# --- Comparaciones -------------------------------------------------------------------------


def comparar_step_run(por_step: Snapshot, por_run: Snapshot) -> list[str]:
    """Diferencias entre el final por STEP y el final por RUN (AC2)."""
    diferencias = []
    if por_step.motivo is not por_run.motivo:
        diferencias.append(
            f"motivo {nombre_motivo(por_step.motivo)} (RUN: {nombre_motivo(por_run.motivo)})"
        )
    cambios = diff(por_run, por_step)
    diferencias += [f"x{n} = 0x{s:08x} (RUN: 0x{r:08x})" for n, (r, s) in cambios.regs.items()]
    diferencias += [
        f"[0x{d:03x}] = 0x{s:08x} (RUN: 0x{r:08x})" for d, (r, s) in cambios.memoria.items()
    ]
    return diferencias


# --- Corrida -------------------------------------------------------------------------------


def verificar_programa(sesion: DebugSession, archivo: Path, con_step: bool) -> list[Resultado]:
    """LOAD → RUN → comparar; con `con_step`, también LOAD → STEP… → comparar contra RUN."""
    nombre = archivo.name
    try:
        imagen = ensamblar(archivo.read_text(encoding="utf-8"))
    except (OSError, ErrorEnsamblado) as error:
        return [Resultado(nombre, "RUN", FALLA, detalle=f"no ensambla: {error}")]
    modelo = GoldenModel(imagen.palabras)
    if modelo.run(MAX_INSTR) is MotivoISS.TIMEOUT:
        return [Resultado(nombre, "RUN", OMITIDO, detalle="no termina en el golden model")]
    esperado = modelo.estado_final()

    resultados = []
    try:
        sesion.load(imagen.palabras)
        por_run = _correr(sesion)
    except (ErrorSesion, ErrorTrama, OSError) as error:  # OSError incluye TimeoutError
        return [Resultado(nombre, "RUN", FALLA, detalle=str(error))]
    resultados.append(_resultado(nombre, "RUN", por_run, comparar(por_run, esperado)))

    if con_step:
        # La placa necesita más ciclos que instrucciones (llenado, stalls, flushes): 4 por
        # instrucción es un techo holgado; pasarlo es un cuelgue.
        maximo = 4 * modelo.instrucciones_retiradas + 10
        try:
            sesion.load(imagen.palabras)
            por_step = _correr_por_step(sesion, maximo)
        except (ErrorSesion, ErrorTrama, OSError) as error:
            return [*resultados, Resultado(nombre, "STEP", FALLA, detalle=str(error))]
        if por_step is None:
            detalle = f"no terminó en {maximo} STEP"
            return [*resultados, Resultado(nombre, "STEP", FALLA, detalle=detalle)]
        diferencias = comparar_step_run(por_step, por_run)
        resultados.append(_resultado(nombre, "STEP", por_step, diferencias))
    return resultados


def _correr(sesion: DebugSession) -> Snapshot:
    """RUN; si se cuelga, ABORT (para dejar la placa lista para el próximo) y error."""
    try:
        return sesion.run()
    except TimeoutError:
        sesion.abort()
        raise TimeoutError(f"no terminó en {sesion.timeouts.run} s (se mandó ABORT)") from None


def _correr_por_step(sesion: DebugSession, maximo: int) -> Snapshot | None:
    for _ in range(maximo):
        snap = sesion.step()
        if snap.estado is EstadoDU.HALTED:
            return snap
    return None


def _resultado(nombre: str, modo: str, snap: Snapshot, diferencias: list[str]) -> Resultado:
    if diferencias:
        return Resultado(nombre, modo, FALLA, snap.ciclos, "; ".join(diferencias))
    return Resultado(nombre, modo, PASA, snap.ciclos)


def verificar_suite(
    sesion: DebugSession, archivos: Iterable[Path], con_step: bool
) -> list[Resultado]:
    resultados = []
    for archivo in archivos:
        nuevos = verificar_programa(sesion, archivo, con_step)
        for r in nuevos:
            print(f"{r.resultado:<7} {r.programa} ({r.modo}) {r.detalle}".rstrip())
        resultados += nuevos
    return resultados


def programas(rutas: Iterable[Path]) -> list[Path]:
    """Los .asm de `rutas`: archivos tal cual, carpetas recorridas en orden.

    Al recorrer una carpeta se saltean las `errores/`: son ejemplos que no ensamblan a
    propósito (para ver cómo los marca la GUI).
    """
    archivos: list[Path] = []
    for ruta in rutas:
        if ruta.is_dir():
            archivos += sorted(a for a in ruta.rglob("*.asm") if "errores" not in a.parts)
        else:
            archivos.append(ruta)
    return archivos


# --- Reporte -------------------------------------------------------------------------------


def reporte(resultados: list[Resultado], encabezado: dict[str, str]) -> str:
    """Markdown para `docs/informe/datos/resultados_placa.md`."""
    run = [r for r in resultados if r.modo == "RUN" and r.resultado != OMITIDO]
    pasan = sum(r.resultado == PASA for r in run)
    porcentaje = f"{100 * pasan / len(run):.1f} %" if run else "-"
    renglones = ["# Resultados en placa (US-411)", ""]
    renglones += [f"- **{clave}:** {valor}" for clave, valor in encabezado.items()]
    renglones += [
        f"- **Pasan en RUN (North Star, AC1):** {pasan} de {len(run)} ({porcentaje})",
        f"- **Reprogramaciones seguidas sin RESET (AC3):** {len(run)}",
        "",
        "| Programa | Modo | Resultado | Ciclos | Detalle |",
        "| -------- | ---- | --------- | ------ | ------- |",
    ]
    for r in resultados:
        ciclos = "" if r.ciclos is None else str(r.ciclos)
        detalle = r.detalle.replace("|", "\\|")
        renglones.append(f"| {r.programa} | {r.modo} | {r.resultado} | {ciclos} | {detalle} |")
    return "\n".join(renglones) + "\n"


def _commit() -> str:
    """Commit del repo, con `-dirty` si hay cambios sin commitear (AC4)."""
    try:
        salida = subprocess.run(
            ["git", "describe", "--always", "--dirty", "--abbrev=12"],  # noqa: S607
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "desconocido (no se pudo correr git)"
    return salida.stdout.strip()


def _sha256(archivo: Path) -> str:
    return hashlib.sha256(archivo.read_bytes()).hexdigest()


# --- main ----------------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Corre la suite en la placa y la compara.")
    parser.add_argument(
        "rutas", type=Path, nargs="*", default=[SUITE], help=".asm o carpetas (por defecto, asm/)"
    )
    parser.add_argument("--step", action="store_true", help="también corre todo con STEP (AC2)")
    parser.add_argument("--port", help="puerto serie (por defecto, el de la Basys 3 detectado)")
    parser.add_argument("--fake", action="store_true", help="usa FakeTransport en vez de la placa")
    parser.add_argument("--bitstream", type=Path, help="el .bit programado, para su hash (AC4)")
    parser.add_argument("--reporte", type=Path, help="escribe el reporte en Markdown acá")
    parser.add_argument(
        "--timeout-run", type=float, default=_TIMEOUT_RUN_S, help="segundos máximos por RUN"
    )
    args = parser.parse_args(argv)

    archivos = programas(args.rutas)
    if not archivos:
        print(f"error: no hay programas .asm en {', '.join(map(str, args.rutas))}", file=sys.stderr)
        return 1
    if args.bitstream is not None and not args.bitstream.is_file():
        print(f"error: no existe el bitstream {args.bitstream}", file=sys.stderr)
        return 1
    try:
        transporte: Transport = FakeTransport() if args.fake else SerialTransport(args.port)
        with DebugSession(transporte, Timeouts(run=args.timeout_run)) as sesion:
            version = sesion.conectar()
            resultados = verificar_suite(sesion, archivos, args.step)
    except (ErrorPuerto, ErrorSesion, ErrorTrama, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    encabezado = {
        "Fecha": datetime.now().astimezone().strftime("%Y-%m-%d %H:%M"),
        "Commit": _commit(),
        "Transporte": "FakeTransport (simulado)" if args.fake else "placa",
        "Protocolo": f"v{version}",
    }
    if args.bitstream is not None:
        encabezado["Bitstream"] = f"`{args.bitstream.name}` · sha256 `{_sha256(args.bitstream)}`"
    texto = reporte(resultados, encabezado)
    if args.reporte is not None:
        args.reporte.parent.mkdir(parents=True, exist_ok=True)
        args.reporte.write_text(texto, encoding="utf-8")
    fallas = [r for r in resultados if r.resultado == FALLA]
    print(f"\n{len(resultados) - len(fallas)} de {len(resultados)} sin fallas")
    return 1 if fallas else 0


if __name__ == "__main__":
    raise SystemExit(main())
