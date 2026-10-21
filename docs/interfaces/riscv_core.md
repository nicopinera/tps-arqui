# Interfaz de `riscv_core`

- **Versión:** 0.1
- **Fecha:** 2026-10-15
- **Historia:** US-103 (AC3, AC5)
- **La implementan:** `hw/rtl/core/riscv_core.v` y `hw/tb/debug/core_stub.v`

Este documento es el **contrato entre la pista A (núcleo) y la pista B (Debug Unit)**. Cualquier cambio en un puerto, un ancho o la posición de un campo en los buses de latches se avisa a la otra pista, sube la versión de este documento y, si afecta a los latches, la versión del formato del snapshot.

## 1. Parámetros

| Parámetro        | Valor por defecto | Descripción                                                             |
| ---------------- | ----------------- | ----------------------------------------------------------------------- |
| `NBIT`           | 32                | Ancho de datos (RV32I)                                                  |
| `IMEM_DEPTH`     | 256               | Palabras (4 bytes) de la IMEM                                           |
| `IMEM_ADDR_BITS` | 8                 | `log2(IMEM_DEPTH)`                                                      |
| `DMEM_DEPTH`     | 256               | Palabras de la DMEM                                                     |
| `DMEM_ADDR_BITS` | 8                 | `log2(DMEM_DEPTH)`                                                      |
| `DEBUG_TRACE`    | 1                 | 1 = los latches posteriores a IF/ID llevan `instr`; 0 = el campo vale 0 |

Los anchos de la sección 4 están calculados con los valores por defecto. `DEBUG_TRACE = 0` **no** cambia los anchos.

## 2. Puertos

Convenciones: prefijos `i_`/`o_`, reset sincrónico activo en alto, un único reloj `clock` sin lógica en su red.

### 2.1 Control de ejecución

| Puerto         | Dir. | Ancho | Descripción                                                                                                                                                                                                       |
| -------------- | ---- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `clock`        | in   | 1     | Reloj del sistema (red global)                                                                                                                                                                                    |
| `i_reset`      | in   | 1     | Reset sincrónico global: PC = 0, 4 latches con `valid = 0`, registros en 0, bitmap y contador en 0, `o_halted = o_illegal = 0`. No borra IMEM ni DMEM (son LUTRAM)                                                |
| `i_enable`     | in   | 1     | Clock enable de **todo** el estado del núcleo: PC, latches, escritura del banco, escritura de DMEM del núcleo, bitmap. STEP = 1 ciclo en 1; RUN = nivel en 1 (R-EJ-2)                                             |
| `i_flush_all`  | in   | 1     | Igual que `i_reset`, salvo bitmap y contador (eso lo hace `i_clear_used`). **Actúa aunque `i_enable = 0`**: la Debug Unit lo usa con el núcleo congelado en `LOAD`/`RESET`                                        |
| `i_stop_fetch` | in   | 1     | Nivel. Mientras vale 1 (con `i_enable = 1`): el PC no cambia, IF/ID e ID/EX reciben burbujas (la instrucción que estaba en ID se descarta) y lo que ya estaba en EX, MEM y WB termina normalmente. Lo usa `ABORT` |
| `o_halted`     | out  | 1     | Nivel. Se activa cuando un HALT **o** una ilegal llega a WB (R-EJ-5) y se mantiene hasta `i_reset` o `i_flush_all`. Mientras vale 1, el núcleo ignora `i_enable`                                                  |
| `o_illegal`    | out  | 1     | Nivel. Vale 1 junto con `o_halted` si lo que se retiró fue una instrucción ilegal. Motivo de terminación: `o_halted && !o_illegal` → `HALTED`; `o_halted && o_illegal` → `ILLEGAL`                                |
| `o_pc`         | out  | 32    | Valor actual del registro PC (cabecera del snapshot, ADR-017)                                                                                                                                                     |

**Fin del drenado por `ABORT`:** el núcleo no tiene una salida dedicada. La Debug Unit considera vacío el pipeline cuando los cuatro bits `valid` de los buses de latches (sección 4) valen 0 (R-EJ-5, ADR-010).

### 2.2 Carga de la IMEM (Debug Unit)

| Puerto         | Dir. | Ancho | Descripción                                                                  |
| -------------- | ---- | ----- | ---------------------------------------------------------------------------- |
| `i_imem_we`    | in   | 1     | Escritura sincrónica de una palabra en la IMEM. **No** depende de `i_enable` |
| `i_imem_addr`  | in   | 8     | Dirección **de palabra** (`IMEM_ADDR_BITS`)                                  |
| `i_imem_wdata` | in   | 32    | Palabra a escribir                                                           |

La Debug Unit solo escribe en `IDLE`, `LOADING` o `HALTED`. El núcleo no lo verifica.

### 2.3 DMEM: limpieza y memoria usada (Debug Unit)

| Puerto            | Dir. | Ancho | Descripción                                                                                                                                         |
| ----------------- | ---- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `i_dbg_dmem_we`   | in   | 1     | Escribe **ceros** en la palabra `i_dbg_dmem_addr`. Toma el mux del puerto de escritura de la DMEM y **no** marca el bitmap. Solo con `i_enable = 0` |
| `i_dbg_dmem_addr` | in   | 8     | Dirección de palabra para la limpieza (`DMEM_ADDR_BITS`)                                                                                            |
| `i_clear_used`    | in   | 1     | Pone en 0 el bitmap y el contador de palabras usadas. No depende de `i_enable`                                                                      |

### 2.4 Lectura de depuración (combinacional)

| Puerto             | Dir. | Ancho | Descripción                                                                                                              |
| ------------------ | ---- | ----- | ------------------------------------------------------------------------------------------------------------------------ |
| `i_dbg_reg_addr`   | in   | 5     | Registro a leer (tercer puerto del banco)                                                                                |
| `o_dbg_reg_data`   | out  | 32    | Contenido de `x[i_dbg_reg_addr]`; `x0` siempre es 0                                                                      |
| `i_dbg_mem_addr`   | in   | 8     | Dirección de palabra de la DMEM a leer (segundo puerto de lectura, ADR-005)                                              |
| `o_dbg_mem_data`   | out  | 32    | Palabra `DMEM[i_dbg_mem_addr]`                                                                                           |
| `o_dbg_mem_used`   | out  | 1     | Bit del bitmap para `i_dbg_mem_addr` (1 = el programa escribió esa palabra)                                              |
| `o_dbg_used_count` | out  | 9     | Cantidad de palabras usadas, de 0 a `DMEM_DEPTH` (= 256, por eso 9 bits). En el snapshot viaja en 2 B (ADR-008, ADR-017) |

### 2.5 Señales de riesgo del ciclo

Valen lo que la lógica de riesgos decide **en el ciclo actual** (combinacional). Se muestrean con el núcleo congelado (R-DU-3).

| Puerto          | Dir. | Ancho | Descripción                                                                   |
| --------------- | ---- | ----- | ----------------------------------------------------------------------------- |
| `o_stall`       | out  | 1     | Stall de load-use: PC e IF/ID se mantienen, burbuja en ID/EX (ADR-007)        |
| `o_flush_if_id` | out  | 1     | Flush de IF/ID (`jal` en ID, o redirección desde EX) (ADR-006)                |
| `o_flush_id_ex` | out  | 1     | Flush de ID/EX (branch tomado o `jalr` en EX) (ADR-006)                       |
| `o_fwd_a`       | out  | 2     | Selector de forwarding del operando A: `00` banco · `01` MEM/WB · `10` EX/MEM |
| `o_fwd_b`       | out  | 2     | Ídem para el operando B / `store_data`                                        |

### 2.6 Latches como buses planos

| Puerto     | Dir. | Ancho | Bytes en el snapshot |
| ---------- | ---- | ----- | -------------------- |
| `o_if_id`  | out  | 104   | 13                   |
| `o_id_ex`  | out  | 248   | 31                   |
| `o_ex_mem` | out  | 152   | 19                   |
| `o_mem_wb` | out  | 144   | 18                   |
| **Total**  |      | 648   | **81**               |

El detalle bit a bit está en la sección 4.

## 3. Prioridades y semántica en el mismo ciclo

De mayor a menor:

1. `i_reset`
2. `i_flush_all` (actúa aunque `i_enable = 0`)
3. `i_enable = 0` → no cambia ningún elemento de estado del núcleo (los puertos de la Debug Unit de 2.2 y 2.3 sí operan)
4. `o_halted = 1` → el núcleo no avanza aunque `i_enable = 1`
5. Redirección desde EX (branch tomado / `jalr`) → flush de IF/ID e ID/EX
6. `jal` en ID → flush de IF/ID
7. Stall de load-use
8. HALT / ilegal detectado en ID → PC congelado, burbujas en IF/ID

`i_stop_fetch` congela el PC y mete burbujas en IF/ID e ID/EX. Los flushes de EX siguen actuando, pero no reactivan la búsqueda.

## 4. Layout de los buses de latches (AC3)

**Decisión:** cada bus tiene **exactamente el layout de bytes del snapshot** (ADR-017). Así el `du_dumper` serializa cualquier latch con la misma lógica, sin conocer los campos:

- el byte `k` del bloque del snapshot es `bus[8k+7 : 8k]` y se envía primero el byte 0;
- los campos multibyte quedan little-endian sin hacer nada: `pc` ocupa `bus[31:0]` tal cual;
- los campos de menos de 8 bits van alineados al bit bajo de su byte, con el resto en 0;
- los bits de relleno valen siempre 0.

El orden de los bits dentro de cada byte de flags que se fija acá se copia en `docs/protocolo.md` (US-104).

### 4.1 `o_if_id` — 104 bits (13 B)

| Bits       | Byte(s) | Campo      | Ancho útil |
| ---------- | ------- | ---------- | ---------- |
| `[31:0]`   | 0–3     | `pc`       | 32         |
| `[63:32]`  | 4–7     | `pc_plus4` | 32         |
| `[95:64]`  | 8–11    | `instr`    | 32         |
| `[96]`     | 12      | `valid`    | 1          |
| `[103:97]` | 12      | relleno    | —          |

### 4.2 `o_id_ex` — 248 bits (31 B)

| Bits        | Byte(s) | Campo                          | Ancho útil |
| ----------- | ------- | ------------------------------ | ---------- |
| `[31:0]`    | 0–3     | `pc`                           | 32         |
| `[63:32]`   | 4–7     | `pc_plus4`                     | 32         |
| `[95:64]`   | 8–11    | `rs1_data`                     | 32         |
| `[127:96]`  | 12–15   | `rs2_data`                     | 32         |
| `[159:128]` | 16–19   | `imm`                          | 32         |
| `[164:160]` | 20      | `rs1` (relleno `[167:165]`)    | 5          |
| `[172:168]` | 21      | `rs2` (relleno `[175:173]`)    | 5          |
| `[180:176]` | 22      | `rd` (relleno `[183:181]`)     | 5          |
| `[186:184]` | 23      | `funct3` (relleno `[191:187]`) | 3          |
| `[193:192]` | 24      | `alu_op` (relleno `[199:194]`) | 2          |
| `[200]`     | 25      | `valid`                        | 1          |
| `[201]`     | 25      | `reg_write`                    | 1          |
| `[202]`     | 25      | `mem_read`                     | 1          |
| `[203]`     | 25      | `mem_write`                    | 1          |
| `[204]`     | 25      | `alu_src`                      | 1          |
| `[205]`     | 25      | `branch`                       | 1          |
| `[206]`     | 25      | `jump`                         | 1          |
| `[207]`     | 25      | `jalr`                         | 1          |
| `[208]`     | 26      | `halt`                         | 1          |
| `[209]`     | 26      | `illegal`                      | 1          |
| `[210]`     | 26      | `funct7_b5`                    | 1          |
| `[212:211]` | 26      | `result_src`                   | 2          |
| `[215:213]` | 26      | relleno                        | —          |
| `[247:216]` | 27–30   | `instr`                        | 32         |

### 4.3 `o_ex_mem` — 152 bits (19 B)

| Bits        | Byte(s) | Campo                          | Ancho útil |
| ----------- | ------- | ------------------------------ | ---------- |
| `[31:0]`    | 0–3     | `alu_result`                   | 32         |
| `[63:32]`   | 4–7     | `store_data` (rs2 forwardeado) | 32         |
| `[95:64]`   | 8–11    | `pc_plus4`                     | 32         |
| `[100:96]`  | 12      | `rd` (relleno `[103:101]`)     | 5          |
| `[106:104]` | 13      | `funct3` (relleno `[111:107]`) | 3          |
| `[112]`     | 14      | `valid`                        | 1          |
| `[113]`     | 14      | `halt`                         | 1          |
| `[114]`     | 14      | `illegal`                      | 1          |
| `[115]`     | 14      | `reg_write`                    | 1          |
| `[116]`     | 14      | `mem_read`                     | 1          |
| `[117]`     | 14      | `mem_write`                    | 1          |
| `[119:118]` | 14      | `result_src`                   | 2          |
| `[151:120]` | 15–18   | `instr`                        | 32         |

### 4.4 `o_mem_wb` — 144 bits (18 B)

| Bits        | Byte(s) | Campo                      | Ancho útil |
| ----------- | ------- | -------------------------- | ---------- |
| `[31:0]`    | 0–3     | `alu_result`               | 32         |
| `[63:32]`   | 4–7     | `mem_data` (ya extendido)  | 32         |
| `[95:64]`   | 8–11    | `pc_plus4`                 | 32         |
| `[100:96]`  | 12      | `rd` (relleno `[103:101]`) | 5          |
| `[104]`     | 13      | `valid`                    | 1          |
| `[105]`     | 13      | `halt`                     | 1          |
| `[106]`     | 13      | `illegal`                  | 1          |
| `[107]`     | 13      | `reg_write`                | 1          |
| `[109:108]` | 13      | `result_src`               | 2          |
| `[111:110]` | 13      | relleno                    | —          |
| `[143:112]` | 14–17   | `instr`                    | 32         |
