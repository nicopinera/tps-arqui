"""Qué es cada campo de los latches (página "Campos" del Pipeline), sin Flet.

Para cada campo: cuántos bits tiene en el hardware, en qué grupo se muestra (Datos, Control,
Depuración), qué es, por qué viaja al latch siguiente y quién lo usa. Sale de
`docs/guias/guia-estudio-datapath.md` §2 y de ADR-017 (formato del volcado). El orden de cada
latch es el del protocolo, el mismo de `campos_latch`.

Los grupos:
- **Datos:** valores que calcula o lee el pipeline (operandos, resultados, direcciones).
- **Control:** señales de la unidad de control que deciden qué hace cada etapa siguiente.
- **Depuración:** viajan solo para que la Debug Unit pueda mostrar la instrucción.
"""

from dataclasses import dataclass

DATOS, CONTROL, DEPURACION = "Datos", "Control", "Depuración"
GRUPOS = (DATOS, CONTROL, DEPURACION)


@dataclass(frozen=True)
class Campo:
    nombre: str
    bits: int
    grupo: str
    que: str
    por_que: str  # por qué viaja hasta este latch
    quien: str  # quién lo lee


_VALID = Campo(
    "valid",
    1,
    CONTROL,
    "1 si hay una instrucción de verdad; 0 es una burbuja.",
    "Una burbuja o una instrucción descartada (flush) tiene que seguir bajando sin efectos.",
    "Las escrituras (registros, memoria) y los forwarders solo actúan con valid = 1.",
)
_HALT = Campo(
    "halt",
    1,
    CONTROL,
    "La instrucción es HALT (opcode custom-0, ADR-004).",
    "El procesador se detiene cuando HALT llega a WB: así terminan las de adelante.",
    "La Debug Unit, en WB: congela el núcleo y pasa a HALTED.",
)
_ILLEGAL = Campo(
    "illegal",
    1,
    CONTROL,
    "La palabra no es ninguna instrucción conocida.",
    "Igual que halt: se espera a que las anteriores terminen.",
    "La Debug Unit, en WB: detiene todo con motivo ILLEGAL.",
)
_REG_WRITE = Campo(
    "reg_write",
    1,
    CONTROL,
    "La instrucción escribe un registro (rd).",
    "La escritura pasa recién en WB.",
    "WB (habilita el banco) y los forwarders: solo se adelanta desde una etapa que va a escribir.",
)
_RESULT_SRC = Campo(
    "result_src",
    2,
    CONTROL,
    "Qué se escribe en rd: 00 ALU, 01 memoria, 10 PC+4 (jal/jalr).",
    "Se decide en ID pero el resultado se elige en WB.",
    "El mux de WB (ResultW), y por lo tanto también el forwarding desde MEM/WB.",
)
_MEM_READ = Campo(
    "mem_read",
    1,
    CONTROL,
    "Es un load (lb, lh, lw, lbu, lhu).",
    "La lectura pasa en MEM.",
    "La Hazard Unit: un load en EX con un dependiente en ID es un load-use (stall).",
)
_MEM_WRITE = Campo(
    "mem_write",
    1,
    CONTROL,
    "Es un store (sb, sh, sw).",
    "La escritura pasa en MEM.",
    "La DMEM (con valid) y el bitmap de memoria usada.",
)
_FUNCT3 = Campo(
    "funct3",
    3,
    CONTROL,
    "Variante de la instrucción (bits 14:12).",
    "En EX distingue la operación y beq/bne; en MEM, el tamaño y el signo del acceso.",
    "alu_control y branch_cmp (EX); store_align y load_extend (MEM).",
)
_RD = Campo(
    "rd",
    5,
    DATOS,
    "Registro destino.",
    "Se escribe en WB, tres etapas después de decodificarlo.",
    "WB (dirección de escritura) y los forwarders, que lo comparan con rs1/rs2 de EX.",
)
_PC4 = Campo(
    "pc_plus4",
    32,
    DATOS,
    "Dirección de la instrucción siguiente.",
    "jal y jalr guardan PC+4 en rd (dirección de vuelta), y eso se escribe en WB.",
    "El mux de WB con result_src = 10. La GUI saca de acá el PC (pc_plus4 - 4).",
)


def _instr(quien: str, grupo: str = DEPURACION) -> Campo:
    return Campo(
        "instr",
        32,
        grupo,
        "La palabra de la instrucción.",
        "Una copia para la Debug Unit: el hardware ya no la necesita después de decodificar.",
        quien,
    )


CAMPOS: dict[str, list[Campo]] = {
    "IF/ID": [
        Campo(
            "pc",
            32,
            DATOS,
            "Dirección de la instrucción buscada.",
            "ID la necesita para calcular el destino de jal (pc + imm).",
            "El sumador de jal en ID; después sigue a ID/EX para branches y jalr.",
        ),
        _PC4,
        _instr(
            "El decodificador y imm_gen en ID: de acá salen rs1, rs2, rd, imm y el control.", DATOS
        ),
        _VALID,
    ],
    "ID/EX": [
        Campo(
            "pc",
            32,
            DATOS,
            "Dirección de la instrucción.",
            "El destino de un branch se calcula en EX: pc + imm.",
            "El sumador de branch en EX.",
        ),
        _PC4,
        Campo(
            "rs1_data",
            32,
            DATOS,
            "Valor de rs1 leído del banco en ID.",
            "Es el operando A de la ALU, que trabaja en EX.",
            "El mux de forwarding A: si fwd_a ≠ 00 se descarta y se usa el valor adelantado.",
        ),
        Campo(
            "rs2_data",
            32,
            DATOS,
            "Valor de rs2 leído del banco en ID.",
            "Operando B de la ALU, comparación de branches y dato de un store.",
            "El mux de forwarding B; después alu_src, branch_cmp y store_data.",
        ),
        Campo(
            "imm",
            32,
            DATOS,
            "Inmediato ya extendido en signo (imm_gen).",
            "Lo usa la ALU (addi, lw…) y el sumador de branch, los dos en EX.",
            "El mux alu_src y el sumador de branch.",
        ),
        Campo(
            "rs1",
            5,
            DATOS,
            "Número del registro fuente 1.",
            "El valor ya se leyó, pero hace falta el número para detectar dependencias.",
            "La Forwarding Unit (lo compara con rd de EX/MEM y MEM/WB).",
        ),
        Campo(
            "rs2",
            5,
            DATOS,
            "Número del registro fuente 2.",
            "Igual que rs1.",
            "La Forwarding Unit.",
        ),
        _RD,
        _FUNCT3,
        Campo(
            "alu_op",
            2,
            CONTROL,
            "Tipo de operación según la unidad de control.",
            "La ALU trabaja en EX.",
            "alu_control: junto con funct3 y funct7_b5 arma alu_ctrl (ADR-019).",
        ),
        _VALID,
        _REG_WRITE,
        _MEM_READ,
        _MEM_WRITE,
        Campo(
            "alu_src",
            1,
            CONTROL,
            "Operando B de la ALU: 0 registro, 1 inmediato.",
            "El mux está en EX.",
            "El mux alu_src.",
        ),
        Campo(
            "branch",
            1,
            CONTROL,
            "Es beq o bne.",
            "Los branches se resuelven en EX (ADR-006).",
            "redirect_ex: si se cumple la condición, pc_sel = 10 y flush de IF/ID e ID/EX.",
        ),
        Campo(
            "jump",
            1,
            CONTROL,
            "Es jal.",
            "jal ya saltó en ID, pero sigue bajando para escribir PC+4 en rd.",
            "Nadie más en EX: la marca queda para depurar.",
        ),
        Campo(
            "jalr",
            1,
            CONTROL,
            "Es jalr.",
            "El destino (rs1 + imm) & ~1 depende de un registro: se resuelve en EX.",
            "El mux ex_target y redirect_ex.",
        ),
        _HALT,
        _ILLEGAL,
        Campo(
            "funct7_b5",
            1,
            CONTROL,
            "El bit 30 de la instrucción (add/sub, srl/sra).",
            "Distingue operaciones en EX.",
            "alu_control.",
        ),
        _RESULT_SRC,
        _instr("La Debug Unit (y la GUI, que la desensambla)."),
    ],
    "EX/MEM": [
        Campo(
            "alu_result",
            32,
            DATOS,
            "Resultado de la ALU (en un load o store, la dirección).",
            "MEM la usa como dirección; si no, es lo que se va a escribir en rd.",
            "La DMEM (dirección) y el forwarding 10 hacia EX.",
        ),
        Campo(
            "store_data",
            32,
            DATOS,
            "Dato a guardar (rs2, ya con forwarding).",
            "La escritura de un store pasa en MEM.",
            "store_align, que lo ubica en el byte correcto.",
        ),
        _PC4,
        _RD,
        _FUNCT3,
        _VALID,
        _HALT,
        _ILLEGAL,
        _REG_WRITE,
        _MEM_READ,
        _MEM_WRITE,
        _RESULT_SRC,
        _instr("La Debug Unit."),
    ],
    "MEM/WB": [
        Campo(
            "alu_result",
            32,
            DATOS,
            "Resultado de la ALU.",
            "Se escribe en rd en WB (result_src = 00).",
            "El mux de WB y el forwarding 01 hacia EX.",
        ),
        Campo(
            "mem_data",
            32,
            DATOS,
            "Dato leído de la DMEM, ya extendido (load_extend).",
            "Un load escribe rd en WB (result_src = 01).",
            "El mux de WB y el forwarding 01.",
        ),
        _PC4,
        _RD,
        _VALID,
        _HALT,
        _ILLEGAL,
        _REG_WRITE,
        _RESULT_SRC,
        _instr("La Debug Unit."),
    ],
}
