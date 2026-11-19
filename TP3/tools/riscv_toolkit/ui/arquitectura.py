"""Qué muestran las vistas de registros y memoria (US-504), sin Flet: se prueba con pytest.

Lo que cambió se mide contra el snapshot **anterior** del historial con `session/diff.py`.
Después de un RUN el anterior es el de antes de correr, así que se resalta todo lo que cambió
en la corrida.
"""

from dataclasses import dataclass

from riscv_toolkit.protocol.comandos import DMEM_DEPTH
from riscv_toolkit.protocol.snapshot import Snapshot
from riscv_toolkit.session.diff import diff


@dataclass(frozen=True)
class FilaRegistro:
    nombre: str  # "x5"
    hexa: str  # "0xffffffff"
    con_signo: str  # "-1"
    sin_signo: str  # "4294967295"
    cambio: bool


@dataclass(frozen=True)
class FilaMemoria:
    direccion: str  # "0x0010"
    hexa: str  # la palabra: "0x00006948"
    bytes_: tuple[str, ...]  # en orden de dirección: +0 (el menos significativo) … +3
    ascii: str  # un carácter por byte, en el mismo orden; "." si no es imprimible
    cambio: bool
    bytes_cambiados: tuple[bool, ...]  # AC2: cuál de los 4 bytes cambió


def _bytes(palabra: int) -> list[int]:
    """Little-endian: el byte de la dirección +0 es el menos significativo (como `sb`)."""
    return [(palabra >> (8 * i)) & 0xFF for i in range(4)]


def filas_registros(actual: Snapshot | None, anterior: Snapshot | None) -> list[FilaRegistro]:
    """Las 32 filas; sin snapshot, todo en 0. `anterior` None: nada resaltado."""
    regs = actual.regs if actual is not None else (0,) * 32
    cambios = diff(anterior, actual).regs if actual is not None and anterior is not None else {}
    return [
        FilaRegistro(
            f"x{n}",
            f"0x{v:08x}",
            str(v - (1 << 32) if v >> 31 else v),
            str(v),
            n in cambios,
        )
        for n, v in enumerate(regs)
    ]


def filas_memoria(
    palabras: dict[int, int], anteriores: dict[int, int] | None = None
) -> list[FilaMemoria]:
    """Una fila por palabra, ordenadas por dirección.

    `anteriores`: la memoria del snapshot anterior (`mem_usada`); None = nada resaltado (un
    rango leído a pedido no se compara con nada). Lo que no está vale 0 (ADR-008), el mismo
    criterio que `diff`.
    """
    filas = []
    for direccion in sorted(palabras):
        valor = palabras[direccion]
        nuevos = _bytes(valor)
        viejos = _bytes(anteriores.get(direccion, 0)) if anteriores is not None else nuevos
        filas.append(
            FilaMemoria(
                f"0x{direccion:04x}",
                f"0x{valor:08x}",
                tuple(f"{b:02x}" for b in nuevos),
                "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in nuevos),
                nuevos != viejos,
                tuple(n != v for n, v in zip(nuevos, viejos, strict=True)),
            )
        )
    return filas


def rango_pedido(direccion: str, cantidad: str) -> tuple[int, int]:
    """Valida lo que escribió el usuario para `DUMP_MEM`: (dirección en bytes, palabras).

    Acepta `0x10`, `16`, `0b10000`. `ValueError` con un mensaje para mostrar si no sirve: así
    no se manda un rango que la DU rechazaría con NACK(RANGO).
    """
    try:
        addr, n = int(direccion.strip(), 0), int(cantidad.strip(), 0)
    except ValueError:
        raise ValueError("Dirección y cantidad tienen que ser números (0x10 o 16).") from None
    if addr < 0 or addr % 4:
        raise ValueError("La dirección tiene que estar alineada a 4 (0x0, 0x4, 0x8…).")
    if n < 1 or addr // 4 + n > DMEM_DEPTH:
        raise ValueError(f"El rango se pasa de la DMEM: hay {DMEM_DEPTH} palabras (0x000…0x3fc).")
    return addr, n


def rango_desde_hasta(desde: str, hasta: str) -> tuple[int, int]:
    """Como `rango_pedido`, pero con las dos direcciones (las dos incluidas): 0x0…0x1c son 8."""
    try:
        d, h = int(desde.strip(), 0), int(hasta.strip(), 0)
    except ValueError:
        raise ValueError("Desde y hasta tienen que ser números (0x10 o 16).") from None
    if h < d:
        raise ValueError("Hasta tiene que ser mayor o igual que desde.")
    if h % 4:
        raise ValueError("Hasta tiene que estar alineada a 4 (0x0, 0x4, 0x8…).")
    return rango_pedido(desde, str((h - d) // 4 + 1))
