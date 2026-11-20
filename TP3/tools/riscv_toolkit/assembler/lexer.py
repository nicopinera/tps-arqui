"""Lexer: corta una línea de assembly en tokens (US-106).

Solo reconoce las piezas; si tienen sentido juntas lo decide el parser. La expresión regular
está explicada en docs/guias/guia-regex.md.
"""

import re
from dataclasses import dataclass
from enum import Enum, auto

from riscv_toolkit.assembler.errores import ErrorEnsamblado


class TipoToken(Enum):
    ETIQUETA = auto()  # definición `loop:`; el texto queda sin los dos puntos
    DIRECTIVA = auto()  # .word
    REGISTRO = auto()  # x5; si existe lo valida el parser (x32 llega hasta acá)
    INMEDIATO = auto()  # 10, -4, 0x1F
    IDENTIFICADOR = auto()  # mnemónico (addi, nop) o etiqueta usada como operando (loop)
    COMA = auto()
    PAR_ABRE = auto()
    PAR_CIERRA = auto()


@dataclass(frozen=True)
class Token:
    tipo: TipoToken
    texto: str


# En cada posición gana la primera alternativa que encaja, así que el orden importa.
_PATRON = re.compile(
    r"""
      (?P<COMENTARIO>\#.*)
    | (?P<ESPACIO>\s+)
    | (?P<ETIQUETA>[A-Za-z_][A-Za-z0-9_]*):
    | (?P<DIRECTIVA>\.[a-z]+)
    | (?P<REGISTRO>x[0-9]+)\b
    | (?P<INMEDIATO>-?(?:0x[0-9A-Fa-f]+|[0-9]+))\b
    | (?P<IDENTIFICADOR>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<COMA>,)
    | (?P<PAR_ABRE>\()
    | (?P<PAR_CIERRA>\))
    | (?P<OTRO>.)
    """,
    re.VERBOSE,
)


def tokenizar(linea: str, nro_linea: int) -> list[Token]:
    """Tokens de `linea`, sin espacios ni comentario. `nro_linea` es solo para el error."""
    tokens: list[Token] = []
    for m in _PATRON.finditer(linea):
        tipo = m.lastgroup  # nombre del grupo que encajó; None no pasa: todos tienen nombre
        if tipo in ("COMENTARIO", "ESPACIO"):
            continue
        if tipo is None or tipo == "OTRO":
            raise ErrorEnsamblado(nro_linea, f"carácter inesperado {m.group()!r}")
        tokens.append(Token(TipoToken[tipo], m.group(tipo)))
    return tokens
