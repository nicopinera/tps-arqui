"""Parser: de los tokens de cada línea a una `LineaAsm` validada (US-106).

Verifica que cada instrucción tenga los operandos que le corresponden (cantidad, tipo y
registros existentes). No resuelve etiquetas ni controla el rango de los inmediatos: eso lo
hacen la segunda pasada e `isa/formatos.py`.
"""

from dataclasses import dataclass
from enum import Enum, auto

from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.lexer import TipoToken, Token, tokenizar
from riscv_toolkit.isa.registros import REGISTROS


@dataclass(frozen=True)
class LineaAsm:
    etiqueta: str | None  # la que se define en esta línea (`loop:`)
    mnemonico: str | None  # None si la línea solo tiene una etiqueta
    # Registros (su número), inmediatos (su valor) o etiquetas (texto, se resuelven en la
    # segunda pasada), en el orden en que se escriben: `lw x5, -4(x2)` → [5, -4, 2].
    operandos: list[int | str]
    nro_linea: int


class Operando(Enum):
    REG = auto()  # x5
    IMM = auto()  # -4, 0x1F
    ETIQ = auto()  # loop
    MEM = auto()  # -4(x2): offset y registro base


REG, IMM, ETIQ, MEM = Operando.REG, Operando.IMM, Operando.ETIQ, Operando.MEM

# Cómo se escriben los operandos de cada mnemónico (decisión 2-A: la sintaxis es del
# ensamblador, no de isa/). Tiene que cubrir todo INSTRUCCIONES; lo verifica un test.
SINTAXIS: dict[str, tuple[Operando, ...]] = {
    **dict.fromkeys(
        ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"], (REG, REG, REG)
    ),
    **dict.fromkeys(["addi", "slti", "sltiu", "xori", "ori", "andi"], (REG, REG, IMM)),
    **dict.fromkeys(["slli", "srli", "srai"], (REG, REG, IMM)),  # el 0..31 lo valida la 2ª pasada
    **dict.fromkeys(["lb", "lh", "lw", "lbu", "lhu", "jalr"], (REG, MEM)),  # rd, imm(rs1)
    **dict.fromkeys(["sb", "sh", "sw"], (REG, MEM)),  # rs2, imm(rs1)
    **dict.fromkeys(["beq", "bne"], (REG, REG, ETIQ)),
    "lui": (REG, IMM),  # imm = los 20 bits altos, como en GNU
    "jal": (REG, ETIQ),
    "halt": (),
    # Pseudoinstrucciones (ADR-013): las expande la primera pasada.
    "nop": (),
    "mv": (REG, REG),
    "j": (ETIQ,),
    "ret": (),
    # Directiva: la palabra va tal cual a la imagen.
    ".word": (IMM,),
}

# Tokens que forman cada tipo de operando.
_TOKENS: dict[Operando, list[TipoToken]] = {
    REG: [TipoToken.REGISTRO],
    IMM: [TipoToken.INMEDIATO],
    ETIQ: [TipoToken.IDENTIFICADOR],
    MEM: [TipoToken.INMEDIATO, TipoToken.PAR_ABRE, TipoToken.REGISTRO, TipoToken.PAR_CIERRA],
}

# Los que aportan un operando; comas y paréntesis son solo puntuación.
_CON_VALOR = {TipoToken.REGISTRO, TipoToken.INMEDIATO, TipoToken.IDENTIFICADOR}

# Para los mensajes de error.
_USO = {REG: "registro", IMM: "inmediato", ETIQ: "etiqueta", MEM: "offset(registro)"}
_DESCRIPCION = {
    TipoToken.REGISTRO: "un registro",
    TipoToken.INMEDIATO: "un inmediato",
    TipoToken.IDENTIFICADOR: "una etiqueta",
    TipoToken.COMA: "una coma",
    TipoToken.PAR_ABRE: "'('",
    TipoToken.PAR_CIERRA: "')'",
}


def parsear(texto: str) -> list[LineaAsm]:
    """Una `LineaAsm` por línea con contenido; las vacías o con solo un comentario no aparecen."""
    lineas = (_parsear_linea(linea, nro) for nro, linea in enumerate(texto.splitlines(), start=1))
    return [linea for linea in lineas if linea is not None]


def _parsear_linea(texto: str, nro: int) -> LineaAsm | None:
    tokens = tokenizar(texto, nro)
    etiqueta = None
    if tokens and tokens[0].tipo is TipoToken.ETIQUETA:
        etiqueta = tokens.pop(0).texto
    if not tokens:
        return LineaAsm(etiqueta, None, [], nro) if etiqueta else None

    cabeza, *resto = tokens
    sintaxis = SINTAXIS.get(cabeza.texto)
    # El tipo se mira para que en `a: nop:` la segunda etiqueta no pase por el mnemónico `nop`.
    if sintaxis is None or cabeza.tipo not in (TipoToken.IDENTIFICADOR, TipoToken.DIRECTIVA):
        raise ErrorEnsamblado(nro, f"mnemónico desconocido {cabeza.texto!r}")

    # Secuencia exacta de tipos de token que tiene que venir: `addi` → REG , REG , IMM.
    esperado: list[TipoToken] = []
    for i, operando in enumerate(sintaxis):
        if i:
            esperado.append(TipoToken.COMA)
        esperado += _TOKENS[operando]

    uso = " ".join([cabeza.texto, ", ".join(_USO[op] for op in sintaxis)]).strip()
    for pos, tipo in enumerate(esperado):
        if pos == len(resto):
            raise ErrorEnsamblado(nro, f"faltan operandos: se escribe '{uso}'")
        if resto[pos].tipo is not tipo:
            vino = resto[pos].texto
            raise ErrorEnsamblado(nro, f"se esperaba {_DESCRIPCION[tipo]} y vino {vino!r}")
    if len(resto) > len(esperado):
        raise ErrorEnsamblado(nro, f"sobran operandos: se escribe '{uso}'")

    operandos = [_valor(t, nro) for t in resto if t.tipo in _CON_VALOR]
    return LineaAsm(etiqueta, cabeza.texto, operandos, nro)


def _valor(token: Token, nro: int) -> int | str:
    """Número del registro, valor del inmediato o nombre de la etiqueta."""
    if token.tipo is TipoToken.REGISTRO:
        if token.texto not in REGISTROS:
            raise ErrorEnsamblado(nro, f"registro inválido {token.texto!r} (x0..x31)")
        return REGISTROS[token.texto]
    if token.tipo is TipoToken.INMEDIATO:
        return int(token.texto, 16 if "0x" in token.texto else 10)
    return token.texto
