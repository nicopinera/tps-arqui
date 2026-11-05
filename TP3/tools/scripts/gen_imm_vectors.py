"""Genera los vectores de `tb_imm_gen.v` cruzados con `isa/formatos.py`.

Arma un programa con inmediatos positivos, negativos y extremos de cada formato, lo ensambla con
el ensamblador del proyecto y, para cada palabra, calcula el inmediato esperado con los
`decode_*` de `formatos.py`. Escribe dos archivos para `$readmemh`:

- `imm_gen.hex`: una instrucción por línea;
- `imm_gen_esperado.hex`: `<imm_type>_<inmediato>` por línea (9 dígitos hex).

Los dos se versionan; `tests/isa/test_imm_vectors_sync.py` verifica que estén al día.

Uso (desde TP3/tools/):  uv run python -m scripts.gen_imm_vectors
"""

from pathlib import Path

from riscv_toolkit.assembler.assembler import ensamblar
from riscv_toolkit.isa.formatos import (
    CamposB,
    CamposJ,
    decode_b,
    decode_i,
    decode_j,
    decode_s,
    decode_u,
    encode_b,
    encode_j,
)
from riscv_toolkit.isa.instrucciones import INSTRUCCIONES, Formato, identificar

DIR_VECTORES = Path(__file__).resolve().parents[2] / "hw" / "tb" / "core" / "vectores"
RUTA_HEX = DIR_VECTORES / "imm_gen.hex"
RUTA_ESPERADO = DIR_VECTORES / "imm_gen_esperado.hex"

# imm_type de tabla_control.md §1 (IMM_* en control_defs.vh).
IMM_TYPE: dict[Formato, int] = {
    Formato.I: 0b000,
    Formato.S: 0b001,
    Formato.B: 0b010,
    Formato.U: 0b011,
    Formato.J: 0b100,
}

# Inmediatos de 12 bits con signo (I y S): ceros, unos, extremos y patrones alternados.
IMM_12 = [0, 1, -1, 5, -5, 1024, -1024, 1365, -1366, 2046, 2047, -2047, -2048]

# lui: los 20 bits altos (0..0xFFFFF); 0x80000 pone el bit 31 en 1.
IMM_20 = [0x00000, 0x00001, 0x12345, 0x7FFFF, 0x80000, 0xABCDE, 0xFFFFF]

# Offsets extremos de B y J que no entran en un programa de 256 palabras: van como `.word`.
EXTREMOS_B = [-4096, -2, 2, 4094]
EXTREMOS_J = [-1048576, -2, 2, 1048574]


def programa() -> str:
    """Texto ensamblador con los casos de prueba de cada formato."""
    lineas: list[str] = ["inicio:"]

    # I aritmético y loads/jalr: el inmediato es el mismo campo de 12 bits.
    for i, imm in enumerate(IMM_12):
        mnem = ("addi", "slti", "sltiu", "xori", "ori", "andi")[i % 6]
        lineas.append(f"{mnem} x{1 + i % 31}, x{31 - i % 31}, {imm}")
    for imm in (-2048, -1, 0, 4, 2047):
        lineas.append(f"lw x5, {imm}(x6)")
        lineas.append(f"lbu x7, {imm}(x8)")
    lineas.append("jalr x1, -2048(x2)")
    lineas.append("jalr x0, 2047(x1)")

    # Shifts: el campo de 12 bits incluye funct7 (srai tiene el bit 30 en 1).
    for shamt in (0, 1, 31):
        lineas.append(f"slli x3, x4, {shamt}")
        lineas.append(f"srli x3, x4, {shamt}")
        lineas.append(f"srai x3, x4, {shamt}")

    # S: el inmediato está partido en [31:25] y [11:7].
    for i, imm in enumerate(IMM_12):
        mnem = ("sb", "sh", "sw")[i % 3]
        lineas.append(f"{mnem} x{1 + i % 31}, {imm}(x{31 - i % 31})")

    # U
    for imm in IMM_20:
        lineas.append(f"lui x9, {imm:#x}")

    # B y J con etiquetas: hacia atrás (negativo), a sí mismas (0) y hacia adelante (positivo).
    lineas.append("aca_b: beq x1, x2, aca_b")
    lineas.append("bne x3, x4, inicio")
    lineas.append("beq x5, x6, fin")
    lineas.append("aca_j: jal x1, aca_j")
    lineas.append("jal x0, inicio")
    lineas.append("jal x1, fin")

    # B y J extremos, codificados con formatos.py.
    beq = INSTRUCCIONES["beq"]
    for imm in EXTREMOS_B:
        campos_b = CamposB(opcode=beq.opcode, funct3=beq.funct3 or 0, rs1=1, rs2=2, imm=imm)
        lineas.append(f".word {encode_b(campos_b):#010x}")
    jal = INSTRUCCIONES["jal"]
    for imm in EXTREMOS_J:
        lineas.append(f".word {encode_j(CamposJ(opcode=jal.opcode, rd=1, imm=imm)):#010x}")

    lineas.append("fin: halt")
    return "\n".join(lineas) + "\n"


def inmediato(palabra: int, formato: Formato) -> int:
    """Inmediato de 32 bits (complemento a dos) según `formatos.py`."""
    match formato:
        case Formato.I:
            valor = decode_i(palabra).imm
        case Formato.S:
            valor = decode_s(palabra).imm
        case Formato.B:
            valor = decode_b(palabra).imm
        case Formato.U:
            valor = decode_u(palabra).imm
        case Formato.J:
            valor = decode_j(palabra).imm
        case _:
            raise ValueError(f"{formato} no tiene inmediato")
    return valor & 0xFFFFFFFF


def generar() -> tuple[str, str]:
    """Devuelve (contenido de imm_gen.hex, contenido de imm_gen_esperado.hex)."""
    texto = programa()
    fuente = texto.splitlines()
    imagen = ensamblar(texto)

    lineas_hex = ["// GENERADO por tools/scripts/gen_imm_vectors.py. NO EDITAR A MANO."]
    lineas_esp = [
        "// GENERADO por tools/scripts/gen_imm_vectors.py. NO EDITAR A MANO.",
        "// <imm_type>_<inmediato>, calculado con los decode_* de isa/formatos.py.",
    ]
    for indice, palabra in enumerate(imagen.palabras):
        spec = identificar(palabra)
        if spec is None or spec.formato not in IMM_TYPE:
            continue  # HALT (y R, que no tiene inmediato) no van al vector
        linea_fuente = fuente[imagen.mapa_lineas[4 * indice] - 1].strip()
        imm = inmediato(palabra, spec.formato)
        lineas_hex.append(f"{palabra:08x}  // {linea_fuente}")
        lineas_esp.append(f"{IMM_TYPE[spec.formato]:x}_{imm:08x}  // {linea_fuente}")
    return "\n".join(lineas_hex) + "\n", "\n".join(lineas_esp) + "\n"


def main() -> None:
    contenido_hex, contenido_esperado = generar()
    DIR_VECTORES.mkdir(parents=True, exist_ok=True)
    # newline="\n": los archivos salen iguales en Windows y en el CI (Linux).
    RUTA_HEX.write_text(contenido_hex, encoding="ascii", newline="\n")
    RUTA_ESPERADO.write_text(contenido_esperado, encoding="ascii", newline="\n")
    print(f"Generados {RUTA_HEX} y {RUTA_ESPERADO} ({contenido_hex.count(chr(10)) - 1} vectores)")


if __name__ == "__main__":
    main()
