"""CLI `rvdbg`: maneja la Debug Unit de la placa desde la terminal (US-410).

Es el subcomando `dbg` de `python -m riscv_toolkit` (se corre desde `TP3/tools/`):

    uv run python -m riscv_toolkit dbg ping                          # ¿responde la placa?
    uv run python -m riscv_toolkit dbg load ../asm/demos/fibonacci.asm
    uv run python -m riscv_toolkit dbg run                           # Ctrl+C manda ABORT
    uv run python -m riscv_toolkit dbg step 5
    uv run python -m riscv_toolkit dbg dump-mem 0x0 12
    uv run python -m riscv_toolkit dbg --fake run --load ../asm/demos/fibonacci.asm
    uv run python -m riscv_toolkit dbg --fake shell                  # modo interactivo

`--port`, `--fake` y `--json` van **antes** de la acción. Con la placa, el estado vive en el
hardware entre una invocación y otra. Con `--fake` la placa simulada vive solo mientras dura el
proceso: por eso `run` y `step` aceptan `--load`, y `shell` usa una sola sesión para todo.

Con `--json` cada acción imprime un objeto JSON en stdout (`{"ok": true, ...}` o
`{"ok": false, "error": ...}`). Sale con 0 si la acción anduvo y con 1 ante cualquier error.
"""

import argparse
import json
import shlex
import sys
from dataclasses import asdict
from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.cli.rvsim import volcado
from riscv_toolkit.disasm.disassembler import desensamblar
from riscv_toolkit.protocol.codec import ErrorTrama
from riscv_toolkit.protocol.comandos import EstadoDU
from riscv_toolkit.protocol.fake_transport import FakeTransport
from riscv_toolkit.protocol.serial_transport import ErrorPuerto, SerialTransport
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.protocol.transport import Transport
from riscv_toolkit.session.debug_session import DebugSession, ErrorSesion

_EXITO = 0
_ERROR = 1

Salida = tuple[str, dict[str, object]]  # texto para personas, datos para --json


class ErrorArchivo(Exception):  # noqa: N818
    """El .asm no se pudo leer o no ensambla. El mensaje ya tiene `archivo:línea:`."""


# OSError cubre el cable desconectado en medio de la sesión (SerialException) y TimeoutError.
_ERRORES = (ErrorSesion, ErrorTrama, ErrorPuerto, ErrorArchivo, OSError)


def agregar_subcomando(
    subcomandos: "argparse._SubParsersAction[argparse.ArgumentParser]",
) -> None:
    """Registra `dbg` en el parser de `__main__.py`."""
    parser = subcomandos.add_parser(
        "dbg",
        help="maneja la Debug Unit de la placa (rvdbg)",
        description="Carga, corre, avanza y vuelca el procesador de la placa por la UART.",
    )
    parser.add_argument("--port", help="puerto serie (por defecto, el de la Basys 3 detectado)")
    parser.add_argument(
        "--fake", action="store_true", help="usa la placa simulada (golden model), sin hardware"
    )
    parser.add_argument("--json", action="store_true", help="salida en JSON, para scripts")
    acciones = parser.add_subparsers(title="acciones", dest="accion", required=True)
    _agregar_acciones(acciones)
    acciones.add_parser("shell", help="modo interactivo: varias acciones en la misma sesión")
    parser.set_defaults(ejecutar=ejecutar)


def _agregar_acciones(acciones: "argparse._SubParsersAction[argparse.ArgumentParser]") -> None:
    """Las acciones de la sesión. Las comparten la línea de comandos y `shell`."""
    p = acciones.add_parser("ping", help="verifica que la Debug Unit responda")
    p.set_defaults(funcion=_ping)

    p = acciones.add_parser("load", help="ensambla un .asm y lo carga en la IMEM")
    p.add_argument("archivo", type=Path, help="programa en assembly (.asm)")
    p.set_defaults(funcion=_load)

    p = acciones.add_parser("run", help="corre hasta HALT o una ilegal (Ctrl+C manda ABORT)")
    _opcion_load(p)
    p.set_defaults(funcion=_run)

    p = acciones.add_parser("step", help="avanza N ciclos (por defecto 1)")
    p.add_argument("n", type=_positivo, nargs="?", default=1, help="cantidad de ciclos")
    _opcion_load(p)
    p.set_defaults(funcion=_step)

    p = acciones.add_parser("dump", help="muestra el estado sin ejecutar nada")
    p.set_defaults(funcion=_dump)

    p = acciones.add_parser("dump-mem", help="lee N palabras de la DMEM desde ADDR")
    p.add_argument("addr", type=_entero, help="dirección en bytes (acepta 0x...)")
    p.add_argument("n", type=_entero, help="cantidad de palabras")
    p.set_defaults(funcion=_dump_mem)

    p = acciones.add_parser("reset", help="vuelve al inicio del programa cargado")
    p.set_defaults(funcion=_reset)

    p = acciones.add_parser("abort", help="corta una ejecución en curso")
    p.set_defaults(funcion=_abort)


def _opcion_load(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--load", type=Path, metavar="ARCHIVO", help="antes, ensambla y carga este .asm"
    )


def _entero(texto: str) -> int:
    return int(texto, 0)  # base 0: acepta 16, 0x10 y 0b10000


def _positivo(texto: str) -> int:
    valor = _entero(texto)
    if valor < 1:
        raise argparse.ArgumentTypeError("tiene que ser al menos 1")
    return valor


# --- Ejecución -----------------------------------------------------------------------------


def ejecutar(args: argparse.Namespace) -> int:
    """Abre la placa (o el fake), se conecta y corre la acción. Devuelve el código de salida."""
    try:
        with DebugSession(_abrir(args)) as sesion:
            sesion.conectar()
            if args.accion == "shell":
                _shell(sesion, args.json)
            else:
                _mostrar(args.funcion(sesion, args), args.json)
    except _ERRORES as error:
        _mostrar_error(error, args.json)
        return _ERROR
    except KeyboardInterrupt:  # Ctrl+C fuera de run (que lo convierte en ABORT)
        _mostrar_error(KeyboardInterrupt("interrumpido"), args.json)
        return _ERROR
    return _EXITO


def _abrir(args: argparse.Namespace) -> Transport:
    return FakeTransport() if args.fake else SerialTransport(args.port)


def _shell(sesion: DebugSession, como_json: bool) -> None:
    """Lee acciones de a una y las corre en la misma sesión, hasta `salir` o fin de entrada."""
    parser = argparse.ArgumentParser(prog="rvdbg>", description="Acciones de la sesión.")
    _agregar_acciones(parser.add_subparsers(title="acciones", dest="accion", required=True))
    print("rvdbg: escribí una acción (-h para la lista) o 'salir'.")
    while True:
        try:
            renglon = input("rvdbg> ")
        except (EOFError, KeyboardInterrupt):
            print()
            return
        try:
            palabras = shlex.split(renglon)
            if palabras[:1] in (["salir"], ["exit"], ["quit"]):
                return
            if not palabras:
                continue
            args = parser.parse_args(palabras)
        except (ValueError, SystemExit):  # comillas sin cerrar, o argparse ya mostró el error
            continue
        try:
            _mostrar(args.funcion(sesion, args), como_json)
        except _ERRORES as error:
            _mostrar_error(error, como_json)


def _mostrar(salida: Salida, como_json: bool) -> None:
    texto, datos = salida
    print(json.dumps({"ok": True, **datos}) if como_json else texto)


def _mostrar_error(error: BaseException, como_json: bool) -> None:
    mensaje = str(error)
    if isinstance(error, TimeoutError):
        mensaje += " (¿la placa está conectada y programada con el bitstream de la Debug Unit?)"
    if como_json:
        print(json.dumps({"ok": False, "error": mensaje}))
    else:
        print(f"error: {mensaje}", file=sys.stderr)


# --- Acciones: cada una recibe la sesión y sus argumentos, y devuelve qué mostrar ----------


def _ping(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    version = sesion.ping()
    return f"Debug Unit OK (protocolo v{version})", {"version": version}


def _load(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    imagen = _cargar(sesion, args.archivo)
    return (
        f"{args.archivo}: {len(imagen.palabras)} palabras cargadas",
        {"palabras": len(imagen.palabras)},
    )


def _run(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    if args.load is not None:
        _cargar(sesion, args.load)
    try:
        snapshot = sesion.run()
    except KeyboardInterrupt:
        print("Ctrl+C: mandando ABORT", file=sys.stderr)
        snapshot = sesion.abort()
    return _salida_snapshot(snapshot)


def _step(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    if args.load is not None:
        _cargar(sesion, args.load)
    avance = []
    for _ in range(args.n):
        snapshot = sesion.step()
        avance.append(f"ciclo {snapshot.ciclos:>5}: pc 0x{snapshot.pc:03x}")
        if snapshot.estado is EstadoDU.HALTED:
            break
    texto, datos = _salida_snapshot(snapshot)
    return "\n".join([*avance[:-1], texto]), datos  # el último ciclo ya está en el resumen


def _dump(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    return _salida_snapshot(sesion.dump())


def _dump_mem(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    rango = sesion.dump_mem(args.addr, args.n)
    texto = "\n".join(f"0x{d:03x}: 0x{dato:08x}" for d, dato in rango.como_dict().items())
    return texto, {"addr": rango.addr, "palabras": list(rango.palabras)}


def _reset(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    sesion.reset()
    return "RESET: el programa vuelve a empezar", {}


def _abort(sesion: DebugSession, args: argparse.Namespace) -> Salida:
    return _salida_snapshot(sesion.abort())


def _cargar(sesion: DebugSession, archivo: Path) -> Imagen:
    try:
        imagen = ensamblar(archivo.read_text(encoding="utf-8"))
    except OSError as error:
        raise ErrorArchivo(f"{archivo}: no se pudo leer: {error.strerror}") from error
    except ErrorEnsamblado as error:
        raise ErrorArchivo(f"{archivo}:{error.linea}: {error.mensaje}") from error
    for advertencia in imagen.advertencias:
        print(f"{archivo}: advertencia: {advertencia}", file=sys.stderr)
    sesion.load(imagen.palabras)
    return imagen


# --- Formato del snapshot ------------------------------------------------------------------


def _salida_snapshot(snapshot: Snapshot) -> Salida:
    return formatear_snapshot(snapshot), snapshot_a_dict(snapshot)


def formatear_snapshot(snap: Snapshot) -> str:
    """Resumen, registros, memoria usada, latches y riesgos, para leer en la terminal."""
    motivo = f" · motivo {snap.motivo.name}" if snap.motivo is not None else ""
    simulado = "  (simulado: un ciclo = una instrucción)" if snap.simulado else ""
    renglones = [
        f"{snap.estado.name}{motivo} · {snap.ciclos} ciclos · pc 0x{snap.pc:03x}{simulado}"
    ]
    renglones.append(volcado(snap.regs, snap.mem_usada).rstrip("\n"))
    latches = [
        ("IF/ID ", snap.if_id.valid, snap.if_id.pc, snap.if_id.instr),
        ("ID/EX ", snap.id_ex.valid, snap.id_ex.pc, snap.id_ex.instr),
        ("EX/MEM", snap.ex_mem.valid, snap.ex_mem.pc_plus4 - 4, snap.ex_mem.instr),
        ("MEM/WB", snap.mem_wb.valid, snap.mem_wb.pc_plus4 - 4, snap.mem_wb.instr),
    ]
    for nombre, valido, pc, instr in latches:
        detalle = f"0x{pc:03x}  {desensamblar(instr, pc)}" if valido else "(burbuja)"
        renglones.append(f"{nombre}  {detalle}")
    r = snap.riesgos
    banderas = (("stall", r.stall), ("flush IF/ID", r.flush_if_id), ("flush ID/EX", r.flush_id_ex))
    marcas = [nombre for nombre, activa in banderas if activa]
    marcas += [f"fwd {op}={_FUENTE_FWD[f]}" for op, f in (("A", r.fwd_a), ("B", r.fwd_b)) if f]
    if marcas:
        renglones.append("riesgos: " + ", ".join(marcas))
    return "\n".join(renglones)


_FUENTE_FWD = {1: "MEM/WB", 2: "EX/MEM", 3: "?"}  # protocolo §6.2; 3 no se usa


def snapshot_a_dict(snap: Snapshot) -> dict[str, object]:
    """El snapshot como datos de JSON: nombres en vez de códigos y la memoria como lista."""
    datos = asdict(snap)
    datos["estado"] = snap.estado.name
    datos["motivo"] = snap.motivo.name if snap.motivo is not None else None
    datos["mem_usada"] = [{"addr": d, "dato": v} for d, v in snap.mem_usada.items()]
    return datos
