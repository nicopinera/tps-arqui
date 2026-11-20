"""Exportar una sesión a JSON y reabrirla sin placa (US-505).

Para el informe, o para mostrar en la defensa si la placa falla. Cada snapshot se guarda como
el payload del protocolo en hex (`Snapshot.to_bytes`): no hay un segundo formato que mantener,
y al reabrir se decodifica con el mismo código que en vivo, así que se ve exactamente igual
(AC2).

    {
      "formato": "riscv-tp3-sesion", "version": 1,
      "fuente": "addi x1, x0, 5\\n...",     # el .asm cargado (o null si no se sabe)
      "programa": [5243027, ...],            # las palabras cargadas (o null)
      "simulado": false,                     # FakeTransport o placa
      "cursor": 12,                          # el ciclo que se estaba mirando
      "snapshots": ["0300000000...", ...]
    }

El archivo viene de afuera: `leer` valida todo y cualquier problema es `ErrorSesionGuardada`
con un mensaje para mostrar.
"""

import json
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from riscv_toolkit.protocol.codec import ErrorTrama
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.session.history import SnapshotHistory

FORMATO = "riscv-tp3-sesion"
VERSION = 1


class ErrorSesionGuardada(ValueError):  # noqa: N818 (como ErrorTrama: el nombre dice qué es)
    """El archivo no es una sesión exportada, o está dañado."""


@dataclass
class SesionGuardada:
    fuente: str | None
    programa: list[int] | None
    historial: SnapshotHistory  # con el cursor donde estaba


def exportar(
    ruta: Path,
    historial: SnapshotHistory,
    programa: Sequence[int] | None,
    fuente: str | None,
) -> None:
    snapshots = list(historial)
    datos = {
        "formato": FORMATO,
        "version": VERSION,
        "fuente": fuente,
        "programa": list(programa) if programa is not None else None,
        "simulado": any(s.simulado for s in snapshots),
        "cursor": historial.indice,
        "snapshots": [s.to_bytes().hex() for s in snapshots],
    }
    ruta.write_text(json.dumps(datos, indent=1, ensure_ascii=False), encoding="utf-8")


def leer(ruta: Path) -> SesionGuardada:
    """`ErrorSesionGuardada` si no se puede leer, no es una sesión o algo no cierra."""
    try:
        datos = json.loads(ruta.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ErrorSesionGuardada(f"No se pudo leer {ruta.name}: {error}") from None
    if not isinstance(datos, dict) or datos.get("formato") != FORMATO:
        raise ErrorSesionGuardada(f"{ruta.name} no es una sesión exportada por la GUI.")
    if datos.get("version") != VERSION:
        raise ErrorSesionGuardada(
            f"{ruta.name} es de la versión {datos.get('version')}; esta GUI lee la {VERSION}."
        )
    fuente, programa = datos.get("fuente"), datos.get("programa")
    textos, cursor = datos.get("snapshots"), datos.get("cursor")
    if fuente is not None and not isinstance(fuente, str):
        raise ErrorSesionGuardada("'fuente' tiene que ser texto.")
    if programa is not None and not (
        isinstance(programa, list)
        and all(isinstance(p, int) and 0 <= p < 1 << 32 for p in programa)
    ):
        raise ErrorSesionGuardada("'programa' tiene que ser una lista de palabras de 32 bits.")
    if not isinstance(textos, list) or not textos:
        raise ErrorSesionGuardada("La sesión no tiene snapshots.")
    if not isinstance(cursor, int) or not 0 <= cursor < len(textos):
        raise ErrorSesionGuardada("'cursor' no apunta a ningún snapshot.")

    historial = SnapshotHistory()
    simulado = datos.get("simulado") is True
    for i, texto in enumerate(textos):
        try:
            historial.agregar(Snapshot.from_bytes(bytes.fromhex(texto), simulado=simulado))
        except (TypeError, ValueError, ErrorTrama) as error:
            raise ErrorSesionGuardada(f"El snapshot {i} está dañado: {error}") from None
    historial.ir_a(cursor)
    return SesionGuardada(fuente, programa, historial)
