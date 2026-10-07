# ADR-019 — Reutilización de la ALU del TP1

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-201
- **Relacionados:** ADR-006 (resolución de branches en EX), ADR-007 (forwarding en la entrada de la ALU)

## Contexto

La ALU del TP1 (`alu.v`) funciona en placa, pero fue diseñada para otro problema:

- es de **8 bits** (RV32I necesita 32);
- usa **opcodes de 6 bits propios, heredados de MIPS** (`100000` = ADD, etc.), que no tienen relación con los campos de RISC-V;
- le faltan `SLL`, `SLT` y `SLTU`, y tiene `NOR`, que RV32I no usa (PRD §1.1, problema 2);
- calcula un flag de overflow que RV32I no usa (no hay excepciones aritméticas).

Además, el datapath necesita resolver en EX la comparación de `beq`/`bne` (ADR-006) y calcular el destino de `jalr`.

## Decisión

### ALU nueva de 32 bits con código interno de 4 bits

- Se escribe una ALU nueva (`hw/rtl/core/alu.v`) de 32 bits, parametrizada (`NBIT = 32`).
- La operación se selecciona con **`alu_ctrl[3:0]`**, un código interno generado por `alu_control.v` a partir de `alu_op` (de la unidad de control), `funct3` y `funct7[5]`.
- Operaciones:

  | `alu_ctrl` | Operación                 | Usada por                                                                   |
  | ---------- | ------------------------- | --------------------------------------------------------------------------- |
  | `ADD`      | `a + b`                   | `add`, `addi`, loads, stores (dirección), `jalr` (destino, antes de `& ~1`) |
  | `SUB`      | `a − b`                   | `sub`                                                                       |
  | `SLL`      | `a << b[4:0]`             | `sll`, `slli`                                                               |
  | `SLT`      | `$signed(a) < $signed(b)` | `slt`, `slti`                                                               |
  | `SLTU`     | `a < b` sin signo         | `sltu`, `sltiu`                                                             |
  | `XOR`      | `a ^ b`                   | `xor`, `xori`                                                               |
  | `SRL`      | `a >> b[4:0]`             | `srl`, `srli`                                                               |
  | `SRA`      | `$signed(a) >>> b[4:0]`   | `sra`, `srai`                                                               |
  | `OR`       | `a \| b`                  | `or`, `ori`                                                                 |
  | `AND`      | `a & b`                   | `and`, `andi`                                                               |
  | `PASS_B`   | `b`                       | `lui` (el inmediato ya viene desplazado desde `imm_gen`)                    |

  Los valores numéricos se definen como `localparam` en un `.vh` compartido entre `alu.v` y `alu_control.v`.

- **Se conserva el estilo del TP1:** un `case` sobre el código de operación, valor por defecto al inicio del `always @(*)`, puertos `i_`/`o_`, sin números mágicos.
- **Se elimina el flag de overflow.** Se mantiene una salida `o_zero` solo si resulta útil para depuración; no se usa en el datapath.

### Comparador de branches separado

- `beq`/`bne` se resuelven con un **comparador de igualdad dedicado en EX** (`branch_cmp`: `eq = (op_a == op_b)`), en paralelo con la ALU, sobre los operandos ya forwardeados (ADR-007).
- La decisión de salto es `branch && (funct3 == BEQ ? eq : !eq)`.
- La ALU queda libre para operaciones aritméticas; `jalr` usa la ALU (`ADD`) para calcular `rs1 + imm`, y el `& ~1` se aplica a la salida antes del mux del PC.

## Alternativas consideradas

**ALU:**

| Opción                                                    | Ventajas                                                                                         | Desventajas                                                                                              |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| **(a) Reescribir con código interno de 4 bits** (elegida) | Código pensado para RISC-V; `alu_control` aísla la ALU de la ISA; menos bits de control en ID/EX | Se reescribe un módulo que ya funcionaba (aunque es chico)                                               |
| (b) Extender la del TP1 (`MSB = 32`, opcodes MIPS)        | Continuidad con el TP1                                                                           | Opcodes de 6 bits sin relación con RISC-V; traducción extra en `alu_control`; arrastra NOR y overflow    |
| (c) `{funct7[5], funct3}` directo como selector           | Mínima lógica                                                                                    | La ALU queda atada a la codificación de la ISA; loads, stores, `lui` y `jalr` necesitan casos especiales |

**Comparación de branches:**

| Opción                                    | Ventajas                                                                                           | Desventajas                                                                    |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **(a) Comparador aparte en EX** (elegida) | Un comparador de igualdad es más rápido que una resta de 32 bits; acorta el camino EX → mux del PC | ~32 LUTs extra                                                                 |
| (b) ALU con `SUB` + flag `zero`           | Es el diseño del libro; sin hardware extra                                                         | El camino forwarding → resta → zero → mux del PC es candidato a camino crítico |

## Consecuencias

**Positivas:**

- La ALU cubre exactamente las operaciones de RV32I que se necesitan, nada más.
- `alu_control.v` es el único lugar que traduce campos de la ISA a operaciones: un error de decodificación se corrige ahí.
- El comparador separado reduce el riesgo de que la resolución de branches sea el camino crítico (ADR-016).
- En el informe se presenta como la evolución de la ALU del TP1, con las diferencias justificadas.

**Negativas:**

- Se pierde la verificación en placa que ya tenía la ALU del TP1: hay que hacer un testbench nuevo con casos borde (overflow de `add` sin flag, `sra` de negativos, `sltu` con `-1`, desplazamientos de 0 y 31).
- Un módulo más (`branch_cmp`) en EX.

**Restricciones que impone:**

- `ID/EX` lleva `alu_op` (de la unidad de control), `funct3` y `funct7_b5` para que `alu_control` genere `alu_ctrl` en EX (PRD §3.2).
- La ALU del TP1 se guarda en `hw/rtl/legacy/` solo como referencia, fuera del proyecto de síntesis (US-101).
- El testbench de la ALU (US-201) cubre las 11 operaciones con valores borde.

## Referencias

- PRD §1.1 (problema 2), §3.2, §8 (ADR-019); US-201, US-206, US-207.
- TP1: `alu.v` y su informe.
