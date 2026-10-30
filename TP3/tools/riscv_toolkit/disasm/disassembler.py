"""Desensamblador: de una palabra de 32 bits a su texto en assembly (US-107).

Lo usan la GUI y el golden model para mostrar qué instrucción hay en cada etapa. Reconoce la
instrucción con la misma tabla que el ensamblador (`isa/instrucciones.py`), saca los campos con
los `decode_*` de `isa/formatos.py` y escribe con la sintaxis del parser, así que
`ensamblar(desensamblar(p)) == p` para toda palabra (salvo branches y `jal`, ver `_destino`).
"""

from riscv_toolkit.assembler.parser import MEM, SINTAXIS
from riscv_toolkit.isa.formatos import decode_b, decode_i, decode_j, decode_r, decode_s, decode_u
from riscv_toolkit.isa.instrucciones import INSTRUCCIONES, Formato, InstructionSpec

_PALABRA_MAX = 0xFFFFFFFF
_SHAMT = 0x1F  # imm[4:0] de slli/srli/srai; imm[11:5] es su funct7

# (opcode, funct3, funct7) → instrucción. funct3 y funct7 son None donde la tabla no los usa
# (U, J y HALT no tienen funct3; solo R y los shifts tienen funct7).
_INDICE: dict[tuple[int, int | None, int | None], InstructionSpec] = {
    (i.opcode, i.funct3, i.funct7): i for i in INSTRUCCIONES.values()
}


def _identificar(palabra: int) -> InstructionSpec | None:
    """Instrucción de `palabra`, o None si es ilegal.

    Se prueba de la clave más específica a la menos: `(opcode, funct3, funct7)` encuentra R y
    shifts, `(opcode, funct3)` el resto de I, S y B, y `opcode` solo U, J y HALT. Una
    combinación que no está en la tabla (`slli` con funct7 != 0, `blt`, `mul`…) no encaja en
    ninguna y es ilegal, igual que en `tabla_control.md`.
    """
    campos = decode_r(palabra)  # opcode, funct3 y funct7 están en el mismo lugar en todo tipo
    claves = (
        (campos.opcode, campos.funct3, campos.funct7),
        (campos.opcode, campos.funct3, None),
        (campos.opcode, None, None),
    )

    for c in claves:
        if c in _INDICE:
            return _INDICE[c]
    return None


def desensamblar(palabra: int, pc: int | None = None) -> str:
    """Texto de `palabra` (`0x00A28293` → `addi x5, x5, 10`).

    Cualquier palabra con opcode custom-0 es `halt` y la que no corresponde a ninguna
    de las 33 sale como `.word 0x...`. `pc` es la dirección de la palabra: si se da, el
    destino de un branch o de `jal` se muestra como dirección absoluta (`0x1c`); si no, relativo
    a la instrucción (`.+8`, `.-40`).
    """
    if not 0 <= palabra <= _PALABRA_MAX:
        raise ValueError(f"la palabra no entra en 32 bits: {palabra:#x}")
    spec = _identificar(palabra)
    if spec is None:
        return f".word 0x{palabra:08x}"  # ilegal: .word es la única forma de escribirla

    m = spec.mnemonico
    match spec.formato:
        case Formato.R:
            r = decode_r(palabra)
            return f"{m} x{r.rd}, x{r.rs1}, x{r.rs2}"
        case Formato.I:
            i = decode_i(palabra)
            if SINTAXIS[m][-1] is MEM:  # loads y jalr: rd, imm(rs1)
                return f"{m} x{i.rd}, {i.imm}(x{i.rs1})"
            imm = i.imm & _SHAMT if spec.funct7 is not None else i.imm
            return f"{m} x{i.rd}, x{i.rs1}, {imm}"
        case Formato.S:
            s = decode_s(palabra)
            return f"{m} x{s.rs2}, {s.imm}(x{s.rs1})"
        case Formato.B:
            b = decode_b(palabra)
            return f"{m} x{b.rs1}, x{b.rs2}, {_destino(b.imm, pc)}"
        case Formato.U:
            u = decode_u(palabra)
            return f"{m} x{u.rd}, 0x{u.imm >> 12:x}"  # como se escribe: los 20 bits altos
        case Formato.J:
            j = decode_j(palabra)
            return f"{m} x{j.rd}, {_destino(j.imm, pc)}"
        case Formato.HALT:
            return m


def _destino(offset: int, pc: int | None) -> str:
    """Destino de un salto: absoluto si se conoce el PC, relativo a la instrucción si no.

    El ensamblador solo acepta etiquetas en branches y `jal`, así que este texto no se puede
    volver a ensamblar tal cual: para eso hay que cambiar la dirección por una etiqueta.
    """
    if pc is None:
        return f".{offset:+d}"
    return f"0x{(pc + offset) & _PALABRA_MAX:x}"
