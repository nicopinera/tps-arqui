# Tabla de Señales de Control

- **Versión:** 0.1
- **Fecha:** 2026-10-15
- **Historia:** US-103
- **La implementan:** `hw/rtl/core/control_unit.v`, `hw/rtl/core/alu_control.v`, `hw/rtl/core/imm_gen.v`

Cualquier cambio en esta tabla después de cerrar US-103 se avisa a la otra pista y se sube la versión.

## 1. Codificación de las señales

| Señal        | Ancho | Valores                                                                                   | La usa                         |
| ------------ | ----- | ----------------------------------------------------------------------------------------- | ------------------------------ |
| `reg_write`  | 1     | 1 = escribe `rd` en WB                                                                    | WB, forwarding                 |
| `mem_read`   | 1     | 1 = load (lee DMEM en MEM)                                                                | MEM, hazard unit (load-use)    |
| `mem_write`  | 1     | 1 = store (escribe DMEM en MEM)                                                           | MEM                            |
| `result_src` | 2     | `00` = resultado de la ALU · `01` = dato de memoria · `10` = `PC+4` · `11` = no se usa    | mux de WB, forwarding MEM/WB   |
| `alu_src`    | 1     | 0 = operando B es `rs2` (forwardeado) · 1 = operando B es `imm`                           | mux de EX                      |
| `alu_op`     | 2     | `00` = ADD · `01` = PASS_B · `10` = R-type (`funct3` + `funct7_b5`) · `11` = I aritmético | `alu_control` (EX)             |
| `branch`     | 1     | 1 = `beq`/`bne`; se resuelve en EX con `branch_cmp` y `funct3` (ADR-006, ADR-019)         | EX → mux del PC                |
| `jump`       | 1     | 1 = `jal`; se resuelve en ID (`PC_ID + imm_J`)                                            | ID → mux del PC                |
| `jalr`       | 1     | 1 = `jalr`; destino `(ALU) & ~1` en EX                                                    | EX → mux del PC                |
| `imm_type`   | 3     | `000` = I · `001` = S · `010` = B · `011` = U · `100` = J · `101`–`111` = no se usan      | `imm_gen` (ID)                 |
| `halt`       | 1     | 1 = HALT o ilegal: detiene la búsqueda, no escribe nada (ADR-004, ADR-018)                | ID (stop fetch), latches, DU   |
| `illegal`    | 1     | 1 = instrucción ilegal (siempre junto con `halt = 1`)                                     | latches, DU (estado `ILLEGAL`) |
| `uses_rs1`   | 1     | 1 = la instrucción realmente lee `rs1`                                                    | hazard unit (ADR-007)          |
| `uses_rs2`   | 1     | 1 = la instrucción realmente lee `rs2`                                                    | hazard unit (ADR-007)          |

**Notas de diseño:**

- `jump` y `jalr` son **excluyentes**: `jump` marca solo `jal` (redirección en ID, 1 ciclo de penalidad) y `jalr` marca solo `jalr` (redirección en EX, 2 ciclos). La redirección desde EX es `(branch && taken) || jalr`; la de ID es `jump`.
- El tamaño y el signo de loads/stores **no** generan señales propias: viajan como `funct3` en ID/EX y EX/MEM, y los interpreta MEM (US-210).
- No hay mux de operando A: `lui` usa `PASS_B` y la dirección de retorno de `jal`/`jalr` viaja como `pc_plus4` (ADR-019).
- **`—` en la tabla** significa que la señal no se usa para esa instrucción. `control_unit` emite el valor por defecto (0), y `tb_control_unit.v` no la verifica.

## 2. Señales por instrucción (las 33)

| #   | Instr.  | opcode    | funct3 | funct7    | `reg_write` | `mem_read` | `mem_write` | `result_src` | `alu_src` | `alu_op` | `branch` | `jump` | `jalr` | `imm_type` | `halt` | `uses_rs1` | `uses_rs2` |
| --- | ------- | --------- | ------ | --------- | ----------- | ---------- | ----------- | ------------ | --------- | -------- | -------- | ------ | ------ | ---------- | ------ | ---------- | ---------- |
| 1   | `add`   | `0110011` | `000`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 2   | `sub`   | `0110011` | `000`  | `0100000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 3   | `sll`   | `0110011` | `001`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 4   | `slt`   | `0110011` | `010`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 5   | `sltu`  | `0110011` | `011`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 6   | `xor`   | `0110011` | `100`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 7   | `srl`   | `0110011` | `101`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 8   | `sra`   | `0110011` | `101`  | `0100000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 9   | `or`    | `0110011` | `110`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 10  | `and`   | `0110011` | `111`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 0         | `10`     | 0        | 0      | 0      | —          | 0      | 1          | 1          |
| 11  | `addi`  | `0010011` | `000`  | —         | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 12  | `slti`  | `0010011` | `010`  | —         | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 13  | `sltiu` | `0010011` | `011`  | —         | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 14  | `xori`  | `0010011` | `100`  | —         | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 15  | `ori`   | `0010011` | `110`  | —         | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 16  | `andi`  | `0010011` | `111`  | —         | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 17  | `slli`  | `0010011` | `001`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 18  | `srli`  | `0010011` | `101`  | `0000000` | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 19  | `srai`  | `0010011` | `101`  | `0100000` | 1           | 0          | 0           | `00` ALU     | 1         | `11`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 20  | `lb`    | `0000011` | `000`  | —         | 1           | 1          | 0           | `01` MEM     | 1         | `00`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 21  | `lh`    | `0000011` | `001`  | —         | 1           | 1          | 0           | `01` MEM     | 1         | `00`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 22  | `lw`    | `0000011` | `010`  | —         | 1           | 1          | 0           | `01` MEM     | 1         | `00`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 23  | `lbu`   | `0000011` | `100`  | —         | 1           | 1          | 0           | `01` MEM     | 1         | `00`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 24  | `lhu`   | `0000011` | `101`  | —         | 1           | 1          | 0           | `01` MEM     | 1         | `00`     | 0        | 0      | 0      | `000` I    | 0      | 1          | 0          |
| 25  | `jalr`  | `1100111` | `000`  | —         | 1           | 0          | 0           | `10` PC+4    | 1         | `00`     | 0        | 0      | 1      | `000` I    | 0      | 1          | 0          |
| 26  | `sb`    | `0100011` | `000`  | —         | 0           | 0          | 1           | —            | 1         | `00`     | 0        | 0      | 0      | `001` S    | 0      | 1          | 1          |
| 27  | `sh`    | `0100011` | `001`  | —         | 0           | 0          | 1           | —            | 1         | `00`     | 0        | 0      | 0      | `001` S    | 0      | 1          | 1          |
| 28  | `sw`    | `0100011` | `010`  | —         | 0           | 0          | 1           | —            | 1         | `00`     | 0        | 0      | 0      | `001` S    | 0      | 1          | 1          |
| 29  | `beq`   | `1100011` | `000`  | —         | 0           | 0          | 0           | —            | —         | —        | 1        | 0      | 0      | `010` B    | 0      | 1          | 1          |
| 30  | `bne`   | `1100011` | `001`  | —         | 0           | 0          | 0           | —            | —         | —        | 1        | 0      | 0      | `010` B    | 0      | 1          | 1          |
| 31  | `lui`   | `0110111` | —      | —         | 1           | 0          | 0           | `00` ALU     | 1         | `01`     | 0        | 0      | 0      | `011` U    | 0      | 0          | 0          |
| 32  | `jal`   | `1101111` | —      | —         | 1           | 0          | 0           | `10` PC+4    | —         | —        | 0        | 1      | 0      | `100` J    | 0      | 0          | 0          |
| 33  | `halt`  | `0001011` | —      | —         | 0           | 0          | 0           | —            | —         | —        | 0        | 0      | 0      | —          | 1      | 0          | 0          |
| —   | ilegal  | otro      | —      | —         | 0           | 0          | 0           | —            | —         | —        | 0        | 0      | 0      | —          | 1      | 0          | 0          |

`illegal` vale 0 en las filas 1–33 y 1 solo en la última fila.

**Por qué cada caso particular:**

- **Stores:** `alu_src = 1` porque la ALU calcula `rs1 + imm`. `rs2` no entra a la ALU, pero sí se lee (`uses_rs2 = 1`): es el `store_data` y pasa por el forwarding (ADR-007).
- **Branches:** no usan la ALU. Comparan los operandos forwardeados en `branch_cmp`, y el destino `PC + imm_B` sale de un sumador propio en EX. Por eso `alu_src` y `alu_op` son `—`.
- **`jal`:** el destino se calcula en ID con `imm_J`, así que no usa la ALU. Escribe `PC+4` en `rd`.
- **`jalr`:** usa la ALU (`ADD`, `rs1 + imm_I`). El `& ~1` se aplica a la salida, antes del mux del PC.
- **`lui`:** `imm_gen` ya entrega `imm[31:12] << 12` y la ALU lo deja pasar (`PASS_B`). No lee registros: `x0` en el campo `rs1` no debe generar stalls falsos.
- **HALT e ilegal:** `uses_rs1 = uses_rs2 = 0`, para que una instrucción que no se va a ejecutar no provoque un stall por load-use.

## 3. Combinaciones legales

Cualquier palabra que no figure en esta tabla activa `illegal = 1` y `halt = 1`, con todas las escrituras en 0. `funct7` = `instr[31:25]`.

| opcode    | Tipo         | `funct3` legales                         | Condición sobre `funct7`                           |
| --------- | ------------ | ---------------------------------------- | -------------------------------------------------- |
| `0110011` | R            | `000`, `101`                             | `0000000` o `0100000`                              |
| `0110011` | R            | `001`, `010`, `011`, `100`, `110`, `111` | `0000000`                                          |
| `0010011` | I aritmético | `000`, `010`, `011`, `100`, `110`, `111` | ninguna (los bits [31:25] son parte del inmediato) |
| `0010011` | I shift      | `001`                                    | `0000000`                                          |
| `0010011` | I shift      | `101`                                    | `0000000` o `0100000`                              |
| `0000011` | Load         | `000`, `001`, `010`, `100`, `101`        | ninguna                                            |
| `0100011` | Store        | `000`, `001`, `010`                      | ninguna                                            |
| `1100011` | Branch       | `000`, `001`                             | ninguna                                            |
| `1100111` | `jalr`       | `000`                                    | ninguna                                            |
| `0110111` | `lui`        | cualquiera (es parte del inmediato)      | ninguna                                            |
| `1101111` | `jal`        | cualquiera (es parte del inmediato)      | ninguna                                            |
| `0001011` | HALT         | cualquiera                               | ninguna (se detecta solo por opcode, ADR-004)      |

**Casos ilegales que conviene probar:**

| Palabra / caso                                                         | Por qué es ilegal                                |
| ---------------------------------------------------------------------- | ------------------------------------------------ |
| `0x00000000`                                                           | opcode `0000000` no existe                       |
| `0xFFFFFFFF`                                                           | opcode `1111111` no existe                       |
| Branch con `funct3 = 010`                                              | combinación reservada                            |
| `blt`/`bge`/`bltu`/`bgeu` (`funct3 = 100`…`111`)                       | son RV32I, pero no están entre las implementadas |
| Load con `funct3 = 011`, `110`, `111`                                  | `ld`/`lwu` no existen en RV32I                   |
| Store con `funct3 = 011` o mayor                                       | no existe en RV32I                               |
| `slli` con `funct7 = 0000001` (`shamt[5] = 1`)                         | reservado en RV32                                |
| R-type con `funct7 = 0000001` (`mul`, …)                               | extensión M, no implementada                     |
| `jalr` con `funct3 ≠ 000`                                              | reservado                                        |
| `auipc` (`0010111`), `ecall`/`ebreak` (`1110011`), `fence` (`0001111`) | son RV32I, pero no están entre las implementadas |

## 4. Control de la ALU

| `alu_op` | `funct3` | `funct7_b5` | `alu_ctrl` | Instrucciones                    |
| -------- | -------- | ----------- | ---------- | -------------------------------- |
| `00`     | x        | x           | `ADD`      | loads, stores, `jalr`            |
| `01`     | x        | x           | `PASS_B`   | `lui`                            |
| `10`     | `000`    | 0           | `ADD`      | `add`                            |
| `10`     | `000`    | 1           | `SUB`      | `sub`                            |
| `10`     | `001`    | x           | `SLL`      | `sll`                            |
| `10`     | `010`    | x           | `SLT`      | `slt`                            |
| `10`     | `011`    | x           | `SLTU`     | `sltu`                           |
| `10`     | `100`    | x           | `XOR`      | `xor`                            |
| `10`     | `101`    | 0           | `SRL`      | `srl`                            |
| `10`     | `101`    | 1           | `SRA`      | `sra`                            |
| `10`     | `110`    | x           | `OR`       | `or`                             |
| `10`     | `111`    | x           | `AND`      | `and`                            |
| `11`     | `000`    | **x**       | `ADD`      | `addi` (nunca `SUB`, US-201 AC2) |
| `11`     | `001`    | x           | `SLL`      | `slli`                           |
| `11`     | `010`    | x           | `SLT`      | `slti`                           |
| `11`     | `011`    | x           | `SLTU`     | `sltiu`                          |
| `11`     | `100`    | x           | `XOR`      | `xori`                           |
| `11`     | `101`    | 0           | `SRL`      | `srli`                           |
| `11`     | `101`    | 1           | `SRA`      | `srai`                           |
| `11`     | `110`    | x           | `OR`       | `ori`                            |
| `11`     | `111`    | x           | `AND`      | `andi`                           |

Las combinaciones ilegales no llegan a `alu_control` con efecto: el decodificador las marca en ID y no escriben nada.
