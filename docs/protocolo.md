# Protocolo PC ↔ Debug Unit

- **Versión del protocolo:** `0x01` (la devuelve `PING`)
- **Fecha:** 2026-10-24
- **Historia:** US-104
- **Fuentes:** ADR-002 (UART), ADR-003 (comandos y tramas), ADR-008 (`DUMP_MEM`, memoria usada), ADR-009 (`LOAD`/`RESET`), ADR-010 (`ABORT`), ADR-017 (snapshot), ADR-018 (`ILLEGAL`), [`interfaces/riscv_core.md`](interfaces/riscv_core.md) (bits de los latches)
- **Lo implementan:** `hw/rtl/debug/*` y `tools/riscv_toolkit/protocol/*`

Este documento es el contrato byte a byte entre el hardware y el software. Cualquier cambio en un valor, un campo o un orden **sube la versión del protocolo** y se refleja en `protocol/comandos.py` (la fuente de las constantes en código; `du_defs.vh` se genera desde ahí). Excepción: `HALT_WORD` y `HALT_OPCODE` son de la ISA y viven en `isa/instrucciones.py`.

## 1. Capa física (ADR-002)

| Parámetro | Valor                                      |
| --------- | ------------------------------------------ |
| Velocidad | 19200 bps                                  |
| Formato   | 8E1: 8 bits de dato, paridad par, 1 stop   |
| Orden     | LSB primero (estándar UART)                |
| Duración  | 11 bits por byte → **≈ 0,573 ms por byte** |

**Endianness:** todo campo de más de un byte viaja **little-endian** (byte menos significativo primero), igual que la memoria de RISC-V (ADR-018).

## 2. Constantes compartidas

| Nombre           | Valor        | Origen         | Uso                                                             |
| ---------------- | ------------ | -------------- | --------------------------------------------------------------- |
| `PROTO_VERSION`  | `0x01`       | este documento | Payload de `PING_INFO`                                          |
| `SYNC`           | `0xA5`       | ADR-003        | Primer byte de toda trama FPGA → PC                             |
| `IMEM_DEPTH`     | 256 palabras | ADR-008        | Máximo `N` de `LOAD`                                            |
| `DMEM_DEPTH`     | 256 palabras | ADR-008        | Rango válido de `DUMP_MEM`; máximo `K` de memoria usada         |
| `HALT_WORD`      | `0x0000000B` | ADR-004        | Relleno de la IMEM (opcode _custom-0_ `0001011`)                |
| `HALT_OPCODE`    | `0b0001011`  | ADR-004        | Detección de HALT en ID                                         |
| `SIGNATURE_ADDR` | `0x3FC`      | ADR-014        | Dirección de la firma de éxito/falla de los programas de prueba |
| `RX_TIMEOUT_MS`  | 100 ms       | este documento | Timeout de recepción en hardware (R-DU-6)                       |

## 3. Estados de la Debug Unit

El código numérico se usa en el byte `estado` del snapshot.

| Código | Estado     | Qué significa                                                                                  | ¿Acepta comandos?          |
| ------ | ---------- | ---------------------------------------------------------------------------------------------- | -------------------------- |
| `0`    | `IDLE`     | No hay programa válido en la IMEM (encendido, o después de un `LOAD` fallido)                  | Sí                         |
| `1`    | `LOADING`  | Recibiendo los argumentos de un `LOAD`                                                         | No: los bytes son la carga |
| `2`    | `READY`    | Programa cargado y núcleo limpio, sin ejecutar ningún ciclo                                    | Sí                         |
| `3`    | `RUN`      | Ejecución continua (`i_enable = 1` en todo ciclo)                                              | Solo `ABORT` y `PING`      |
| `4`    | `STEPPING` | Ejecución paso a paso empezada; el núcleo está congelado entre pasos                           | Sí                         |
| `5`    | `DUMPING`  | Recibiendo los argumentos de `DUMP_MEM` o enviando una trama de datos; al terminar vuelve (§5) | No: los bytes se descartan |
| `6`    | `HALTED`   | La ejecución terminó (HALT, instrucción ilegal o `ABORT`); el pipeline está vacío              | Sí                         |

## 4. Comandos PC → FPGA

Un byte de comando ASCII, seguido de argumentos binarios si los tiene (ADR-003).

| Byte         | Comando    | Argumentos                                                                   | Respuesta                                      |
| ------------ | ---------- | ---------------------------------------------------------------------------- | ---------------------------------------------- |
| `0x4C` `'L'` | `LOAD`     | `N` (2 B) + `N` palabras de 4 B + checksum (1 B) = XOR de los `2 + 4N` bytes | `ACK` / `NACK`                                 |
| `0x52` `'R'` | `RUN`      | —                                                                            | `ACK` inmediato; al terminar, `SNAPSHOT` final |
| `0x53` `'S'` | `STEP`     | —                                                                            | `SNAPSHOT`                                     |
| `0x44` `'D'` | `DUMP`     | —                                                                            | `SNAPSHOT`                                     |
| `0x58` `'X'` | `RESET`    | —                                                                            | `ACK`                                          |
| `0x41` `'A'` | `ABORT`    | —                                                                            | `SNAPSHOT` con motivo `ABORTED`                |
| `0x3F` `'?'` | `PING`     | —                                                                            | `PING_INFO` con la versión                     |
| `0x4D` `'M'` | `DUMP_MEM` | dirección inicial en **bytes** (2 B) + cantidad de palabras (2 B)            | `MEM_DATA` / `NACK(ERR_RANGO)`                 |

En los diagramas de paquete se indica arriba de cada campo cuántos bytes ocupa. En los bytes de flags (§6.2) se indica el número de bit, con el bit 7 a la izquierda.

```text
LOAD (3 + 4N + 1 bytes)
 1 B    2 B       4 B           4 B                4 B         1 B
+----+--------+-------------+-------------+-----+---------------+-----+
| 4C | N (LE) | palabra 0   | palabra 1   | ... | palabra N-1   | XOR |
+----+--------+-------------+-------------+-----+---------------+-----+
       \_______________ XOR de estos 2 + 4N bytes ______________/
```

```text
DUMP_MEM (5 bytes)
 1 B    2 B                 2 B
+----+--------------------+------------------+
| 4D | dirección (LE, B)  | n palabras (LE)  |
+----+--------------------+------------------+
```

**Validaciones de argumentos:**

- `LOAD`: `1 ≤ N ≤ IMEM_DEPTH`. Fuera de rango → `NACK(ERR_TAMANO)`.
- `DUMP_MEM`: dirección múltiplo de 4, cantidad `n ≥ 1` y `dirección/4 + n ≤ DMEM_DEPTH`. Si no → `NACK(ERR_RANGO)`.

### 4.1 Comandos válidos por estado (R-DU-1 completa)

OK = se ejecuta · X = `NACK(ERR_ESTADO)`, sin cambiar nada · — = el byte no se interpreta como comando

| Comando     | `IDLE` | `LOADING` | `READY` | `RUN` | `STEPPING` | `DUMPING` | `HALTED` |
| ----------- | ------ | --------- | ------- | ----- | ---------- | --------- | -------- |
| `LOAD`      | OK     | —         | OK      | X     | OK         | —         | OK       |
| `RESET`     | OK ¹   | —         | OK      | X     | OK         | —         | OK       |
| `RUN`       | X      | —         | OK      | X     | OK         | —         | X        |
| `STEP`      | X      | —         | OK      | X     | OK         | —         | X        |
| `DUMP`      | OK     | —         | OK      | X     | OK         | —         | OK       |
| `DUMP_MEM`  | OK     | —         | OK      | X     | OK         | —         | OK       |
| `ABORT`     | X      | —         | X       | OK    | X          | —         | X        |
| `PING`      | OK     | —         | OK      | OK    | OK         | —         | OK       |
| Desconocido | X ²    | —         | X ²     | X ²   | X ²        | —         | X ²      |

¹ Sin programa cargado: responde `ACK` y queda en `IDLE` (ADR-009).
² `NACK(ERR_DESCONOCIDO)` en lugar de `ERR_ESTADO`.

**Estados de paso:**

- **`LOADING`:** todo byte que llega es parte de la carga (`N`, palabras o checksum), aunque coincida con el código de un comando.
- **`DUMPING`:** mientras recibe los 4 bytes de argumentos de `DUMP_MEM`, los bytes son argumentos. Mientras envía una trama, todo byte que llega **se descarta sin respuesta**. La PC no debe mandar nada hasta recibir la trama completa.

## 5. Transiciones por comando

| Comando                  | Desde                              | Hacia                                                                                             |
| ------------------------ | ---------------------------------- | ------------------------------------------------------------------------------------------------- |
| `LOAD` correcto          | `IDLE`/`READY`/`STEPPING`/`HALTED` | `LOADING` → `READY` (IMEM nueva + limpieza completa, ADR-009)                                     |
| `LOAD` fallido           | `LOADING`                          | `IDLE`, con toda la IMEM rellena de HALT (R-DU-4)                                                 |
| `RESET`                  | `READY`/`STEPPING`/`HALTED`        | `READY` (limpia todo menos la IMEM)                                                               |
| `RESET`                  | `IDLE`                             | `IDLE`                                                                                            |
| `RUN`                    | `READY`/`STEPPING`                 | `RUN` → (HALT o ilegal llega a WB, o `ABORT` + drenado) → `DUMPING` → `HALTED`                    |
| `STEP`                   | `READY`/`STEPPING`                 | 1 ciclo con `i_enable = 1` → `DUMPING` → `STEPPING`, o `HALTED` si ese ciclo terminó la ejecución |
| `DUMP`, `DUMP_MEM`       | `IDLE`/`READY`/`STEPPING`/`HALTED` | `DUMPING` → el mismo estado de origen (`r_prev_state`)                                            |
| `PING`, comando inválido | cualquiera                         | sin cambio                                                                                        |
| `i_reset` (botón)        | cualquiera                         | `IDLE`                                                                                            |

**Motivo de terminación:** viaja en el snapshot (§6.2), no es un estado. Los tres motivos terminan en el estado `HALTED`.

| Código | Motivo    | Condición                         |
| ------ | --------- | --------------------------------- |
| `0`    | (ninguno) | La ejecución no terminó           |
| `1`    | `HALTED`  | `o_halted && !o_illegal`          |
| `2`    | `ILLEGAL` | `o_halted && o_illegal` (ADR-018) |
| `3`    | `ABORTED` | Comando `ABORT` (ADR-010)         |

El motivo se conserva en `HALTED`: un `DUMP` posterior lo vuelve a informar. `LOAD` y `RESET` lo ponen en 0.

## 6. Tramas FPGA → PC

```text
[0xA5] [tipo: 1 B] [longitud: 2 B] [payload: longitud B] [checksum: 1 B]
checksum = tipo ⊕ longitud[7:0] ⊕ longitud[15:8] ⊕ payload[0] ⊕ … ⊕ payload[longitud-1]
```

El `0xA5` **no** entra en el checksum.

```text
Trama FPGA → PC (5 + longitud bytes)
 1 B   1 B     2 B           longitud B         1 B
+----+------+-------------+--------------------+-----+
| A5 | tipo | longitud LE | payload            | XOR |
+----+------+-------------+--------------------+-----+
       \______________ XOR de esto ___________/
```

### 6.1 Tipos de trama

| Valor  | Tipo        | Longitud    | Payload                                           |
| ------ | ----------- | ----------- | ------------------------------------------------- |
| `0x01` | `ACK`       | 0           | —                                                 |
| `0x02` | `NACK`      | 1           | código de error (§7)                              |
| `0x03` | `SNAPSHOT`  | `221 + 6·K` | §6.2                                              |
| `0x04` | `PING_INFO` | 1           | `PROTO_VERSION`                                   |
| `0x05` | `MEM_DATA`  | `4 + 4·n`   | dirección (2 B) + `n` (2 B) + `n` palabras de 4 B |

`MEM_DATA` no estaba nombrado en ADR-003. Se agrega acá como la "trama con las palabras pedidas" de ADR-008.

### 6.2 Layout del payload `SNAPSHOT` (ADR-017)

Los offsets son relativos al primer byte del payload. Los latches tienen exactamente el layout de bytes de los buses `o_if_id`…`o_mem_wb`.

| Offset | Tamaño | Bloque / campo                                                            |
| ------ | ------ | ------------------------------------------------------------------------- |
| 0      | 1      | `estado`: bits `[3:0]` = estado de la DU (§3), bits `[7:4]` = motivo (§5) |
| 1      | 4      | contador de ciclos (con `i_enable = 1`, desde el último `LOAD`/`RESET`)   |
| 5      | 4      | PC actual (`o_pc`)                                                        |
| 9      | 1      | riesgos del ciclo (flags, ver abajo)                                      |
| 10     | 128    | `x0` … `x31`, 4 B cada uno (`x0` siempre 0)                               |
| 138    | 13     | IF/ID                                                                     |
| 151    | 31     | ID/EX                                                                     |
| 182    | 19     | EX/MEM                                                                    |
| 201    | 18     | MEM/WB                                                                    |
| 219    | 2      | `K` = palabras usadas (0…256)                                             |
| 221    | 6·K    | `K` × [dirección en bytes (2 B) + dato (4 B)], dirección creciente        |

```text
Payload SNAPSHOT (221 + 6K bytes)
offset  0      1         5      9         10                  138
      +------+---------+------+---------+-------------------+---------+
      |estado| ciclos  |  PC  | riesgos | x0 … x31 (128 B)  | IF/ID   | →
      +------+---------+------+---------+-------------------+---------+
         1 B    4 B      4 B     1 B                          13 B

offset  151       182       201       219   221
      +---------+---------+---------+-----+---------------------------+
    → | ID/EX   | EX/MEM  | MEM/WB  |  K  | K × [dir 2 B | dato 4 B]  |
      +---------+---------+---------+-----+---------------------------+
         31 B      19 B      18 B    2 B        6·K B
```

**Verificación AC2:** 1 + 4 + 4 + 1 + 128 + 13 + 31 + 19 + 18 + 2 = **221**, más `6·K`. Con la memoria llena (`K = 256`), la longitud es 1757 B: entra en los 2 B del campo `longitud`.

`estado` vale `(motivo << 4) | estado_du`. Por ejemplo, `0x16` = motivo `HALTED`, estado `HALTED`; `0x04` = sin motivo, estado `STEPPING`.

**Byte de riesgos (offset 9):**

| Bit   | 7   | 6–5          | 4–3          | 2             | 1             | 0       |
| ----- | --- | ------------ | ------------ | ------------- | ------------- | ------- |
| Campo | 0   | `fwd_b[1:0]` | `fwd_a[1:0]` | `flush_id_ex` | `flush_if_id` | `stall` |

`fwd_x`: `00` = banco, `01` = MEM/WB, `10` = EX/MEM.

Los bytes de flags, bit a bit (bit 7 a la izquierda):

```text
Byte estado (offset 0)
  bit  7     4 3     0
     +-------+-------+
     | motivo| est DU|
     +-------+-------+
```

```text
Byte de riesgos (offset 9)
  bit   7      6 5      4 3       2          1          0
     +-----+--------+--------+---------+---------+-------+
     |  0  | fwd_b  | fwd_a  | fl_idex | fl_ifid | stall |
     +-----+--------+--------+---------+---------+-------+
```

```text
ID/EX flags 1 (byte 25)
  bit    7      6       5       4        3        2        1        0
     +------+------+--------+-------+--------+--------+--------+-------+
     | jalr | jump | branch |alu_src| mem_wr | mem_rd | reg_wr | valid |
     +------+------+--------+-------+--------+--------+--------+-------+

ID/EX flags 2 (byte 26)
  bit   7 6 5       4 3        2          1        0
     +-------+------------+----------+---------+------+
     |   0   | result_src | f7_b5    | illegal | halt |
     +-------+------------+----------+---------+------+
```

```text
EX/MEM flags (byte 14)
  bit    7 6         5        4        3         2        1      0
     +------------+--------+--------+--------+---------+------+-------+
     | result_src | mem_wr | mem_rd | reg_wr | illegal | halt | valid |
     +------------+--------+--------+--------+---------+------+-------+
```

```text
MEM/WB flags (byte 13)
  bit  7 6      5 4          3         2        1      0
     +-----+------------+--------+---------+------+-------+
     |  0  | result_src | reg_wr | illegal | halt | valid |
     +-----+------------+--------+---------+------+-------+
```

**Campos de los latches:**

| Latch (offset) | Byte relativo        | Campo                                                                                                      |
| -------------- | -------------------- | ---------------------------------------------------------------------------------------------------------- |
| IF/ID (138)    | 0–3 / 4–7 / 8–11     | `pc` / `pc_plus4` / `instr`                                                                                |
|                | 12                   | bit 0 `valid`; bits 7–1 = 0                                                                                |
| ID/EX (151)    | 0–3 / 4–7            | `pc` / `pc_plus4`                                                                                          |
|                | 8–11 / 12–15 / 16–19 | `rs1_data` / `rs2_data` / `imm`                                                                            |
|                | 20 / 21 / 22         | `rs1` / `rs2` / `rd` (bits 4–0)                                                                            |
|                | 23 / 24              | `funct3` (bits 2–0) / `alu_op` (bits 1–0)                                                                  |
|                | 25 (flags 1)         | b0 `valid`, b1 `reg_write`, b2 `mem_read`, b3 `mem_write`, b4 `alu_src`, b5 `branch`, b6 `jump`, b7 `jalr` |
|                | 26 (flags 2)         | b0 `halt`, b1 `illegal`, b2 `funct7_b5`, b4–3 `result_src`, b7–5 = 0                                       |
|                | 27–30                | `instr`                                                                                                    |
| EX/MEM (182)   | 0–3 / 4–7 / 8–11     | `alu_result` / `store_data` / `pc_plus4`                                                                   |
|                | 12 / 13              | `rd` (bits 4–0) / `funct3` (bits 2–0)                                                                      |
|                | 14 (flags)           | b0 `valid`, b1 `halt`, b2 `illegal`, b3 `reg_write`, b4 `mem_read`, b5 `mem_write`, b7–6 `result_src`      |
|                | 15–18                | `instr`                                                                                                    |
| MEM/WB (201)   | 0–3 / 4–7 / 8–11     | `alu_result` / `mem_data` / `pc_plus4`                                                                     |
|                | 12                   | `rd` (bits 4–0)                                                                                            |
|                | 13 (flags)           | b0 `valid`, b1 `halt`, b2 `illegal`, b3 `reg_write`, b5–4 `result_src`, b7–6 = 0                           |
|                | 14–17                | `instr`                                                                                                    |

Los bits de relleno valen siempre 0. Un latch con `valid = 0` se envía completo (burbuja). Con `DEBUG_TRACE = 0`, los campos `instr` de ID/EX, EX/MEM y MEM/WB valen 0 y el layout no cambia.

## 7. Errores

### 7.1 Códigos de `NACK`

| Código | Nombre            | Causa                                                        | Estado después                                                                             |
| ------ | ----------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `0x01` | `ERR_DESCONOCIDO` | Byte de comando que no está en §4                            | Sin cambio                                                                                 |
| `0x02` | `ERR_ESTADO`      | Comando válido, pero no en este estado (§4.1)                | Sin cambio                                                                                 |
| `0x03` | `ERR_CHECKSUM`    | El checksum de `LOAD` no coincide                            | `IDLE`, IMEM rellena con HALT                                                              |
| `0x04` | `ERR_TAMANO`      | `LOAD` con `N = 0` o `N > IMEM_DEPTH`                        | `IDLE`, IMEM rellena con HALT                                                              |
| `0x05` | `ERR_RANGO`       | `DUMP_MEM` fuera de rango o con dirección no alineada        | El estado anterior                                                                         |
| `0x06` | `ERR_TIMEOUT`     | Pasaron `RX_TIMEOUT_MS` sin bytes en medio de los argumentos | `LOAD`: `IDLE` + IMEM con HALT · `DUMP_MEM`: estado anterior                               |
| `0x07` | `ERR_PARIDAD`     | Un byte llegó con la paridad incorrecta (ADR-002)            | Igual que `ERR_TIMEOUT` si había argumentos en curso; sin cambio si era un byte de comando |

El código `0x00` no se usa: un `NACK` con payload 0 indica un bug en el serializador.

### 7.2 Errores en medio de los argumentos: drenar y después responder

`ERR_TAMANO` y `ERR_PARIDAD` se pueden detectar **antes** de que termine de llegar el comando. Si la Debug Unit respondiera en ese momento, los bytes restantes (por ejemplo, las palabras de un `LOAD`) se interpretarían como comandos.

Por eso, ante un error detectado en medio de los argumentos de `LOAD` o `DUMP_MEM`, la Debug Unit:

1. deja de interpretar los bytes y los descarta,
2. espera `RX_TIMEOUT_MS` sin recibir bytes (la línea en silencio),
3. recién entonces envía el `NACK` con el código **original** (no `ERR_TIMEOUT`) y pasa al estado de la tabla.

Si llega un byte con error de paridad estando en `RUN`, la ejecución **sigue**: se responde `NACK(ERR_PARIDAD)` y el snapshot final llega igual.

### 7.3 Timeout de recepción (R-DU-6)

- **Tiempo:** 100 ms desde el **último byte recibido**, no desde el inicio del comando. Equivale a ~175 bytes de silencio a 19200 bps: un margen holgado para que la PC no lo dispare entre bytes de una misma carga.
- **En ciclos:** `RX_TIMEOUT_CYCLES = CLK_FREQ_HZ × 0,1` (10 000 000 a 100 MHz, contador de 24 bits). Se calcula como parámetro desde `CLK_FREQ_HZ`, igual que `COUNT_MAX` (ADR-002).
- **Solo corre** en `LOADING` y mientras `DUMPING` recibe argumentos. Se reinicia con cada byte.

### 7.4 Timeout del lado de la PC

- **Recomendado:** 1 s para las respuestas a `ACK`/`NACK`, `PING`, `STEP`, `DUMP`, `DUMP_MEM`. El snapshot más grande tarda ~1 s (ADR-008), así que para `STEP` y `DUMP` se usa 2 s.
- **Para el snapshot final de `RUN`:** no hay timeout corto (ADR-010). La PC espera hasta que el usuario mande `ABORT`.
- **Resincronización:** ante una trama con checksum inválido, la PC descarta bytes hasta el próximo `0xA5`.

## 8. Ejemplos byte a byte (AC1)

Todos los bytes están en hexadecimal. Para todos los ejemplos se usa este programa:

```text
0x00: addi x1, x0, 5   → 0x00500093
0x04: sw   x1, 0(x0)   → 0x00102023
0x08: halt             → 0x0000000B
```

### 8.1 Respuestas fijas

| Trama                   | Bytes               |
| ----------------------- | ------------------- |
| `ACK`                   | `A5 01 00 00 01`    |
| `NACK(ERR_DESCONOCIDO)` | `A5 02 01 00 01 02` |
| `NACK(ERR_ESTADO)`      | `A5 02 01 00 02 01` |
| `NACK(ERR_CHECKSUM)`    | `A5 02 01 00 03 00` |
| `NACK(ERR_TAMANO)`      | `A5 02 01 00 04 07` |
| `NACK(ERR_RANGO)`       | `A5 02 01 00 05 06` |
| `NACK(ERR_TIMEOUT)`     | `A5 02 01 00 06 05` |
| `NACK(ERR_PARIDAD)`     | `A5 02 01 00 07 04` |
| `PING_INFO(0x01)`       | `A5 04 01 00 01 04` |

### 8.2 `LOAD`

```text
PC  → 4C | 03 00 | 93 00 50 00 | 23 20 10 00 | 0B 00 00 00 | D8
         |  N=3  |  palabra 0  |  palabra 1  |  palabra 2  | XOR de los 14 bytes anteriores
FPGA→ A5 01 00 00 01                       (ACK, queda en READY)
```

Con el checksum corrupto (`27` en lugar de `D8`): `A5 02 01 00 03 00` (`NACK(ERR_CHECKSUM)`). Queda en `IDLE` con la IMEM llena de HALT.

### 8.3 `RESET`

```text
PC  → 58
FPGA→ A5 01 00 00 01                       (ACK)
```

### 8.4 `PING`

```text
PC  → 3F
FPGA→ A5 04 01 00 01 04                    (PING_INFO, versión 0x01)
```

### 8.5 `STEP` (desde `READY`, recién cargado el programa) — snapshot completo

Payload de 221 B (`K = 0`): longitud `0x00DD`.

```text
PC  → 53
FPGA→ A5 03 DD 00                          cabecera de trama
      04                                   estado: motivo 0, STEPPING
      01 00 00 00                          ciclos = 1
      04 00 00 00                          PC = 0x00000004
      00                                   riesgos: ninguno
      00 × 128                             x0…x31 = 0
      00 00 00 00 04 00 00 00 93 00 50 00 01   IF/ID: pc=0, pc_plus4=4, instr=addi, valid=1
      00 × 31                              ID/EX: burbuja
      00 × 19                              EX/MEM: burbuja
      00 × 18                              MEM/WB: burbuja
      00 00                                K = 0
      19                                   checksum
```

### 8.6 `DUMP`

Desde `STEPPING`, sin pasos en el medio, es la misma trama que §8.5 (`PC → 44`). La DU vuelve a `STEPPING`.

### 8.7 `RUN` y snapshot final

```text
PC  → 52
FPGA→ A5 01 00 00 01                       ACK inmediato (RUN)
      … el núcleo ejecuta hasta que el HALT llega a WB …
FPGA→ A5 03 E3 00                          SNAPSHOT, longitud 227 = 221 + 6·1
      16                                   estado: motivo HALTED, estado HALTED
      07 00 00 00                          ciclos = 7
      0C 00 00 00                          PC = 0x0000000C (congelado después del HALT)
      00                                   riesgos
      00 00 00 00 | 05 00 00 00 | 00 × 120     x0 = 0, x1 = 5, resto 0
      00 × 81                              latches vacíos (valid = 0)
      01 00                                K = 1
      00 00 05 00 00 00                    [0x0000] = 0x00000005
      FC                                   checksum
```

Los valores de los latches y del contador de ciclos son ilustrativos: dependen de cómo el núcleo deja los campos de una burbuja. Lo que se verifica es el formato.

### 8.8 `ABORT` (programa con loop infinito)

```text
PC  → 52            FPGA → A5 01 00 00 01          (ACK, RUN)
PC  → 41            FPGA → A5 03 DD 00 36 …        (SNAPSHOT, estado 0x36 = ABORTED + HALTED)
```

### 8.9 `DUMP_MEM`

```text
PC  → 4D | 00 00 | 02 00                   desde 0x0000, 2 palabras
FPGA→ A5 05 0C 00 | 00 00 02 00 | 05 00 00 00 | 00 00 00 00 | 0E
         MEM_DATA, len 12 | dir, n | [0x000]=5 | [0x004]=0 | checksum

PC  → 4D | FC 03 | 02 00                   desde 0x3FC, 2 palabras (se pasa del final)
FPGA→ A5 02 01 00 05 06                    NACK(ERR_RANGO), sin cambio de estado
```

### 8.10 Errores de estado

```text
(en IDLE)  PC → 53     FPGA → A5 02 01 00 02 01    NACK(ERR_ESTADO): STEP sin programa
(en RUN)   PC → 44     FPGA → A5 02 01 00 02 01    NACK(ERR_ESTADO): DUMP durante RUN
(cualq.)   PC → 5A     FPGA → A5 02 01 00 01 02    NACK(ERR_DESCONOCIDO): 'Z'
```

## 9. Secuencia típica

Ver [`diagramas/secuencia_protocolo.md`](diagramas/secuencia_protocolo.md): `LOAD` → `STEP` × 3 → `RUN` → snapshot final.
