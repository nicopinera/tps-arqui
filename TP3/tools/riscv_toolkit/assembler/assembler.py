"""Ensamblador de dos pasadas: texto assembly → `Imagen` (US-106, ADR-013).

El recorrido completo está explicado en docs/guias/guia-ensamblador.md.
"""

from dataclasses import replace

from riscv_toolkit.assembler.errores import ErrorEnsamblado
from riscv_toolkit.assembler.imagen import Imagen
from riscv_toolkit.assembler.parser import MEM, SINTAXIS, LineaAsm, parsear
from riscv_toolkit.isa.formatos import (
    CamposB,
    CamposI,
    CamposJ,
    CamposR,
    CamposS,
    CamposU,
    ErrorCodificacion,
    encode_b,
    encode_i,
    encode_j,
    encode_r,
    encode_s,
    encode_u,
)
from riscv_toolkit.isa.instrucciones import HALT_WORD, INSTRUCCIONES, Formato
from riscv_toolkit.protocol.comandos import IMEM_DEPTH

# Cada pseudo se reescribe como texto y se vuelve a parsear: la expansión que se muestra en el
# listado es exactamente la que se codifica. {0}, {1} son los operandos escritos.
_PSEUDO = {
    "nop": "addi x0, x0, 0",
    "mv": "addi x{0}, x{1}, 0",
    "j": "jal x0, {0}",
    "ret": "jalr x0, 0(x1)",
}

_LINEA_HALT_AGREGADO = 0  # el HALT que agrega el ensamblador no viene de ninguna línea

# Alineación que exige cada acceso a memoria (ADR-018); lb, lbu y sb leen o escriben 1 byte.
_ALINEACION = {"lh": 2, "lhu": 2, "sh": 2, "lw": 4, "sw": 4}


def ensamblar(texto: str) -> Imagen:
    """Ensambla un programa completo. Lanza `ErrorEnsamblado` ante el primer error."""
    instrucciones: list[LineaAsm] = []  # la de índice i va en la dirección 4·i
    simbolos: dict[str, int] = {}
    definida_en: dict[str, int] = {}  # etiqueta → línea, para el mensaje de duplicada
    mapa_lineas: dict[int, int] = {}
    expansiones: dict[int, str] = {}
    advertencias: list[str] = []

    # --- Primera pasada: direcciones, tabla de símbolos y pseudoinstrucciones ---
    for linea in parsear(texto):
        direccion = 4 * len(instrucciones)
        if linea.etiqueta is not None:
            if linea.etiqueta in simbolos:
                anterior = definida_en[linea.etiqueta]
                raise ErrorEnsamblado(
                    linea.nro_linea,
                    f"etiqueta {linea.etiqueta!r} duplicada (ya definida en la línea {anterior})",
                )
            simbolos[linea.etiqueta] = direccion
            definida_en[linea.etiqueta] = linea.nro_linea
        if linea.mnemonico is None:
            continue  # etiqueta sola: apunta a la próxima instrucción
        if linea.mnemonico in _PSEUDO:
            real = _PSEUDO[linea.mnemonico].format(*linea.operandos)
            expansiones[direccion] = real
            (expandida,) = parsear(real)
            linea = replace(expandida, etiqueta=linea.etiqueta, nro_linea=linea.nro_linea)
        mapa_lineas[direccion] = linea.nro_linea
        instrucciones.append(linea)

    if not instrucciones or instrucciones[-1].mnemonico != "halt":  # R-PR-1, ADR-010
        instrucciones.append(LineaAsm(None, "halt", [], _LINEA_HALT_AGREGADO))
        advertencias.append("el programa no termina en halt: se agregó uno al final")
    if len(instrucciones) > IMEM_DEPTH:  # R-PR-2, ADR-008
        primera_afuera = instrucciones[IMEM_DEPTH].nro_linea or instrucciones[-2].nro_linea
        raise ErrorEnsamblado(
            primera_afuera,
            f"el programa ocupa {len(instrucciones)} palabras contando el halt final "
            f"y la IMEM tiene {IMEM_DEPTH}",
        )

    # --- Segunda pasada: etiquetas → offsets y codificación ---
    palabras = [_codificar(linea, 4 * i, simbolos) for i, linea in enumerate(instrucciones)]

    # Desalineados (ADR-018): solo se pueden ver sin ejecutar con base x0, donde la dirección
    # es el offset. Loads y stores comparten el orden [rd o rs2, offset, base].
    for linea in instrucciones:
        tam = _ALINEACION.get(linea.mnemonico or "")
        if tam and linea.operandos[2] == 0 and int(linea.operandos[1]) % tam:
            advertencias.append(
                f"línea {linea.nro_linea}: {linea.mnemonico} desalineado: la dirección "
                f"{linea.operandos[1]} no es múltiplo de {tam} y el hardware ignora los "
                "bits bajos (ADR-018)"
            )
    return Imagen(palabras, simbolos, mapa_lineas, expansiones, advertencias)


def _codificar(linea: LineaAsm, direccion: int, simbolos: dict[str, int]) -> int:
    """Palabra de una instrucción ya expandida, con sus etiquetas resueltas."""
    ops = [_resolver(op, linea, direccion, simbolos) for op in linea.operandos]
    assert linea.mnemonico is not None  # noqa: S101 - la primera pasada descarta las etiquetas solas
    if linea.mnemonico == ".word":
        return _palabra_cruda(ops[0], linea.nro_linea)

    spec = INSTRUCCIONES[linea.mnemonico]
    funct3 = spec.funct3 or 0  # None solo en U, J y HALT, que no lo usan
    try:
        match spec.formato:
            case Formato.R:
                rd, rs1, rs2 = ops
                return encode_r(CamposR(spec.opcode, rd, funct3, rs1, rs2, spec.funct7 or 0))
            case Formato.I:
                if SINTAXIS[linea.mnemonico][-1] is MEM:  # loads y jalr: rd, imm(rs1)
                    rd, imm, rs1 = ops
                else:
                    rd, rs1, imm = ops
                if spec.funct7 is not None:  # slli/srli/srai: imm = funct7 | shamt
                    _verificar_rango("shamt", imm, 0, 31, linea.nro_linea)
                    imm |= spec.funct7 << 5
                return encode_i(CamposI(spec.opcode, rd, funct3, rs1, imm))
            case Formato.S:
                rs2, imm, rs1 = ops
                return encode_s(CamposS(spec.opcode, funct3, rs1, rs2, imm))
            case Formato.B:
                rs1, rs2, offset = ops
                return encode_b(CamposB(spec.opcode, funct3, rs1, rs2, offset))
            case Formato.U:
                rd, imm20 = ops  # como en GNU: los 20 bits altos, no el valor de 32
                _verificar_rango("imm de lui", imm20, 0, 0xFFFFF, linea.nro_linea)
                return encode_u(CamposU(spec.opcode, rd, imm20 << 12))
            case Formato.J:
                rd, offset = ops
                return encode_j(CamposJ(spec.opcode, rd, offset))
            case Formato.HALT:  # pragma: no branch - los case cubren todo Formato
                return HALT_WORD
    except ErrorCodificacion as error:  # formatos.py no conoce las líneas: se la agregamos
        raise ErrorEnsamblado(linea.nro_linea, str(error)) from error


def _resolver(op: int | str, linea: LineaAsm, direccion: int, simbolos: dict[str, int]) -> int:
    """Una etiqueta pasa a ser el offset relativo al PC de la instrucción; un número queda igual."""
    if isinstance(op, int):
        return op
    if op not in simbolos:
        raise ErrorEnsamblado(linea.nro_linea, f"etiqueta inexistente {op!r}")
    return simbolos[op] - direccion


def _palabra_cruda(valor: int, nro: int) -> int:
    """`.word`: acepta el valor con o sin signo y lo guarda en 32 bits (-1 → 0xFFFFFFFF)."""
    _verificar_rango(".word", valor, -(1 << 31), 0xFFFFFFFF, nro)
    return valor & 0xFFFFFFFF


def _verificar_rango(nombre: str, valor: int, minimo: int, maximo: int, nro: int) -> None:
    if not minimo <= valor <= maximo:
        raise ErrorEnsamblado(nro, f"{nombre} fuera de rango: {valor} ({minimo}..{maximo})")
