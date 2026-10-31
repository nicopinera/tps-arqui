# Guía de estudio — Datapath RV32I segmentado (TP3)

Este documento tiene como objetivo guiar el estudio del funcionamiento del procesador tipo RISC-V segmentado. Este procesador esta construido basado en el modelo de Harris & Harris, _Digital Design and Computer Architecture: RISC-V Edition_, cap. 7 (procesador segmentado). La Fig. 7.61 es la base del diagrama.

---

## 1. Panorama general

### 1.1 La idea del pipeline

Cada instrucción pasa por 5 etapas, y en cada ciclo hay hasta 5 instrucciones distintas, una en cada etapa:

| Etapa   | Nombre             | Qué hace                                                                              |
| ------- | ------------------ | ------------------------------------------------------------------------------------- |
| **IF**  | Instruction Fetch  | Lee la instrucción apuntada por el PC y calcula `PC + 4`                              |
| **ID**  | Instruction Decode | Decodifica, lee registros, arma el inmediato; resuelve `jal`; detecta HALT e ilegales |
| **EX**  | Execute            | ALU, forwarding, decide branches y `jalr`                                             |
| **MEM** | Memory             | Lee o escribe la memoria de datos                                                     |
| **WB**  | Write Back         | Elige el resultado y lo escribe en el banco de registros                              |

Los **latches** (IF/ID, ID/EX, EX/MEM, MEM/WB) son registros que en cada flanco de reloj capturan todo lo que la instrucción necesita para las etapas siguientes. Pensalos como **la mochila de la instrucción**: lo que no está en la mochila no llega a la etapa siguiente. Por eso se exige que ninguna señal "aparezca" en una etapa sin haber cruzado el latch anterior.

### 1.2 Cómo leer el diagrama

- **Colores:** negro = datos · azul = control y riesgos · naranja = puertos de la Debug Unit.
- **Sufijos:** cada señal lleva la letra de la etapa en la que está: `rdD`, `rdE`, `rdM`, `rdW` son el **mismo campo de distintas instrucciones**. `rdE` es el `rd` de la instrucción que está en EX en este ciclo.
- **Filas fijas:** cada campo viaja siempre a la misma altura, de izquierda a derecha. Por ejemplo, `pc_plus4` está abajo de todo y los controles arriba.
- **Las realimentaciones van por abajo:** `ResultW`, `rdW`, `alu_resultM`, `jal_target` y `ex_target` vuelven hacia la izquierda por debajo de los latches. **Todo cable que va hacia atrás es un riesgo resuelto en hardware o una escritura en WB.**

### 1.3 Decisiones de diseño que tenés que poder defender

| Decisión                                                            | Por qué                                                                                                  | ADR              |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ---------------- |
| Memorias con lectura **combinacional** (LUTRAM)                     | IF y MEM leen en el mismo ciclo; sin alineación especial del PC                                          | ADR-005          |
| `jal` se resuelve en **ID**; branches y `jalr` en **EX**            | `jal` no depende de registros, así que se adelanta (1 ciclo); los otros necesitan operandos forwardeados | ADR-006          |
| Forwarding completo + stall solo para load-use                      | Solo se pierde 1 ciclo, y solo en load-use                                                               | ADR-007          |
| Bypass interno en el banco (en vez de escr. en el flanco de bajada) | Un solo flanco de reloj en todo el diseño                                                                | ADR-007, ADR-001 |
| Comparador de igualdad dedicado (`branch_cmp`)                      | Más rápido que restar con la ALU; acorta el camino crítico                                               | ADR-019          |
| Ilegal = HALT con causa de error                                    | Reutiliza el drenado del HALT; el error queda visible                                                    | ADR-018          |
| `i_enable` como clock enable, nunca compuertas en el reloj          | Un solo dominio de reloj; STEP = 1 ciclo con enable                                                      | ADR-001          |

### 1.4 Los registros

RV32I tiene **32 registros de 32 bits**, `x0` a `x31`, más el **PC**, que no es accesible como registro común.

**Para el hardware los 32 son idénticos, salvo `x0`:**

- **`x0` vale siempre 0.** Leerlo da 0 y escribirlo no tiene efecto: el banco ignora la escritura y el forwarding nunca reenvía un resultado con destino `x0`. No es un registro "inicializado en 0": está **cableado** a 0.
- **`x1` a `x31`** son registros de propósito general. Cualquier instrucción puede leerlos o escribirlos.
- **El PC** solo cambia por el propio flujo del programa: `+4`, branches, `jal` y `jalr`. Para obtenerlo hay que usar `jal`/`jalr`, que guardan `PC + 4` en `rd`.

**Nomeclatura ABI.** Además del número, cada registro tiene un nombre que indica para qué se **acostumbra** usarlo. Es una convención de software (la ABI, _Application Binary Interface_), no una regla del hardware: `addi t0, t0, 1` y `addi x5, x5, 1` son la misma instrucción. **Nuestro ensamblador acepta solo `x0`–`x31`** (ADR-013); la tabla sirve para leer ejemplos de libros o de internet y traducirlos.

| Registro    | Nombre ABI  | Uso por convención                               | ¿Lo preserva una subrutina? |
| ----------- | ----------- | ------------------------------------------------ | --------------------------- |
| `x0`        | `zero`      | Constante 0 (cableado)                           | —                           |
| `x1`        | `ra`        | _Return address_: dirección de retorno de `jal`  | No                          |
| `x2`        | `sp`        | _Stack pointer_: puntero de pila                 | Sí                          |
| `x3`        | `gp`        | _Global pointer_: datos globales                 | —                           |
| `x4`        | `tp`        | _Thread pointer_: datos por hilo                 | —                           |
| `x5`–`x7`   | `t0`–`t2`   | _Temporaries_: temporales                        | No                          |
| `x8`        | `s0` / `fp` | _Saved_ / _frame pointer_                        | Sí                          |
| `x9`        | `s1`        | _Saved_: se conserva entre llamadas              | Sí                          |
| `x10`–`x11` | `a0`–`a1`   | _Arguments_: argumentos **y valores de retorno** | No                          |
| `x12`–`x17` | `a2`–`a7`   | _Arguments_: más argumentos                      | No                          |
| `x18`–`x27` | `s2`–`s11`  | _Saved_: se conservan entre llamadas             | Sí                          |
| `x28`–`x31` | `t3`–`t6`   | _Temporaries_: temporales                        | No                          |

**Qué tenés que saber para este TP:**

1. **`x0`** se usa todo el tiempo:
   - `addi x5, x0, 5` carga 5;
   - `beq x5, x0, fin` salta si `x5` es 0;
   - `sub x6, x0, x5` niega `x5`.
2. **`x1`** (`ra`) es donde, por convención, `jal x1, funcion` guarda la dirección de retorno, y `ret` (= `jalr x0, 0(x1)`) vuelve a ella. Si una subrutina llama a otra sin guardar `x1`, pierde su propia dirección de retorno.
3. **Las demás convenciones** (pila, argumentos, registros que se preservan) solo importan si escribís subrutinas. En los programas de prueba podés usar `x5`–`x31` libremente. El procesador no controla las convenciones.
4. **Valores iniciales:** después de un `LOAD` o un `RESET`, los 32 registros valen 0. `x2` (`sp`) no se inicializa a ninguna dirección: si un programa usa pila, primero tiene que cargarlo con una dirección de la DMEM (de `0x000` a `0x3FF`).
5. **En el datapath:**
   - los campos `rs1`, `rs2` y `rd` de 5 bits son el **número** del registro (0 a 31);
   - el chequeo `rd != 0` del forwarding y de la hazard unit es justamente el caso de `x0`;
   - la Debug Unit lee los 32 registros por el puerto A4/RD4 para el snapshot.

### 1.5 Cómo está codificada una instrucción

Cada instrucción es una palabra de **32 bits**. En IF/ID viaja junto con `pc`, `pc_plus4` y `valid` (104 bits en total), pero lo que se decodifica son esos 32 bits de `instr`.

#### Los formatos

Los 32 bits se reparten en campos, y el reparto depende del **formato**:

```txt
 31        25 24   20 19   15 14  12 11         7 6       0
┌────────────┬───────┬───────┬──────┬────────────┬─────────┐
│   funct7   │  rs2  │  rs1  │funct3│     rd     │ opcode  │  R  → 6 campos
├────────────┴───────┼───────┼──────┼────────────┼─────────┤
│     imm[11:0]      │  rs1  │funct3│     rd     │ opcode  │  I  → 5
├────────────┬───────┼───────┼──────┼────────────┼─────────┤
│ imm[11:5]  │  rs2  │  rs1  │funct3│  imm[4:0]  │ opcode  │  S  → 6 (imm partido)
├────────────┼───────┼───────┼──────┼────────────┼─────────┤
│imm[12|10:5]│  rs2  │  rs1  │funct3│imm[4:1|11] │ opcode  │  B  → 6 (imm partido)
├────────────┴───────┴───────┴──────┼────────────┼─────────┤
│            imm[31:12]             │     rd     │ opcode  │  U  → 3
├───────────────────────────────────┼────────────┼─────────┤
│      imm[20|10:1|11|19:12]        │     rd     │ opcode  │  J  → 3
└───────────────────────────────────┴────────────┴─────────┘
```

- **El opcode está en todos, siempre en los bits `[6:0]`.** Es lo primero que mira la Control Unit.
- **`rs1`, `rs2` y `rd` están siempre en la misma posición** cuando existen. Por eso en ID el banco de registros se puede leer _al mismo tiempo_ que la Control Unit decide qué instrucción es: extraer los campos son solo cables.
- **El inmediato es lo que cambia de lugar** en cada formato. Lo arma `imm_gen` según `imm_type`. Qué bit del inmediato va en qué bit de la palabra, formato por formato y con ejemplos, está en [`interfaces/formatos.md`](../interfaces/formatos.md).

#### opcode → funct3 → funct7: una jerarquía de tres niveles

"funct" viene de _function_. funct3 y funct7 **completan al opcode** para decir exactamente qué instrucción es:

1. **opcode (7 bits) dice la familia.**
   - `0110011` = operación entre registros (R)
   - `0010011` = operación con inmediato
   - `0000011` = load
   - `0100011` = store
   - `1100011` = branch
2. **funct3 (3 bits, `[14:12]`) dice cuál dentro de la familia.** Por ejemplo, con opcode `0110011`:

   | funct3 | Operación     |
   | ------ | ------------- |
   | `000`  | `add` / `sub` |
   | `001`  | `sll`         |
   | `010`  | `slt`         |
   | `011`  | `sltu`        |
   | `100`  | `xor`         |
   | `101`  | `srl` / `sra` |
   | `110`  | `or`          |
   | `111`  | `and`         |

3. **funct7 (7 bits, `[31:25]`) desempata cuando funct3 no alcanza.** En RV32I solo importa un bit, el 30 (`funct7[5]`):

   | funct3 | funct7    | Instrucción |
   | ------ | --------- | ----------- |
   | `000`  | `0000000` | `add`       |
   | `000`  | `0100000` | `sub`       |
   | `101`  | `0000000` | `srl`       |
   | `101`  | `0100000` | `sra`       |

   Por eso a ID/EX y a `alu_control` les llega `funct7_b5` (un solo bit) y no los 7.

   **Ejemplo:** `add x3, x1, x2` (x3 = x1 + x2) y `sub x3, x1, x2` (x3 = x1 − x2) difieren en un único bit:

   ```text
            funct7   rs2   rs1  funct3  rd    opcode
   add:    0000000 00010 00001  000   00011 0110011   = 0x002081B3
   sub:    0100000 00010 00001  000   00011 0110011   = 0x402081B3
            ↑ bit 30
   ```

   Cualquier otro valor de funct7 es **ilegal** en este diseño.

**Por qué está hecho así:**

- **Ahorra opcodes.** Con 7 bits hay 128 combinaciones; agrupando por familia, un solo opcode (R) cubre 10 instrucciones.
- **Simplifica el control.** Las instrucciones de una misma familia usan el datapath igual (todas las R leen dos registros, usan la ALU y escriben `rd`). La Control Unit decide casi todas las señales **solo con el opcode**. funct3 y funct7 importan para elegir la operación de la ALU, y en loads y stores para el tamaño del acceso.

#### funct3 significa otra cosa en cada familia

| Familia | funct3 = `000` | funct3 = `001` | funct3 = `010` |
| ------- | -------------- | -------------- | -------------- |
| R / I   | `add` / `addi` | `sll` / `slli` | `slt` / `slti` |
| Load    | `lb` (byte)    | `lh` (media)   | `lw` (palabra) |
| Store   | `sb`           | `sh`           | `sw`           |
| Branch  | `beq`          | `bne`          | (ilegal)       |

Por eso en este diseño **funct3 viaja en los latches**:

- **hasta EX:** lo usan `alu_control` y `branch_cmp` (`000` = igual, `001` = distinto);
- **hasta MEM:** lo usan `store_align` y `load_extend` para saber si el acceso es de byte, media palabra o palabra, y si se extiende con signo.

#### Trampa: en los otros formatos, esos bits son inmediato

funct7 solo existe en el formato R (y, como caso especial, en los shifts con inmediato: `slli`, `srli`, `srai`). En I, S, B, U y J, los bits `[31:25]` **son parte del inmediato**. ¿Por qué los shifts sí tienen funct7? Correr un registro de 32 bits más de 31 posiciones no tiene sentido, así que la cantidad (`shamt`) entra en 5 bits (`[24:20]`). Los 7 bits de arriba quedan libres y se reusan como funct7.

**Ejemplo:** en `addi x1, x1, -1024` el bit 30 vale 1, pero no significa "resta": es un bit del número. Por eso:

- la Control Unit genera `alu_op = 11` para las I aritméticas;
- `alu_control` ignora `funct7[5]` en `addi`, y solo lo mira cuando `funct3 = 101` (`srli` contra `srai`).

Lo mismo vale para funct3 en U y J: en `lui` y `jal` esos bits también son inmediato.

---

## 2. Etapa por etapa

### 2.1 IF — búsqueda

**Bloques:** mux del PC (`pc_sel`), registro PC, Instruction Memory y sumador `+4`.

- El **registro PC** se actualiza en cada flanco, salvo que `StallF = 1`. `StallF` agrupa tres causas: stall de load-use, HALT detectado (`halt_fetch`) o `i_stop_fetch` (ABORT).
- El **mux del PC** tiene 3 entradas:

  | `pc_sel` | Próximo PC   | Cuándo                                              |
  | -------- | ------------ | --------------------------------------------------- |
  | `00`     | `pc_plus4F`  | Caso normal                                         |
  | `01`     | `jal_target` | Hay un `jal` válido en ID                           |
  | `10`     | `ex_target`  | Branch tomado o `jalr` en EX (**máxima prioridad**) |

  `pc_sel` lo genera la Hazard Unit, porque ella conoce las prioridades.

- La **IMEM** se lee con el PC en el mismo ciclo (combinacional), así que la instrucción entra a IF/ID en el flanco siguiente.
- **Puerto naranja:** `i_imem_we/addr/wdata`. La Debug Unit carga el programa con el núcleo congelado.
- A IF/ID entra `validF = 1`. Las burbujas (`valid = 0`) aparecen por **flush** (CLR) o por halt_fetch.

**IF/ID guarda:** `pc`, `pc_plus4`, `instr` y `valid`.

### 2.2 ID — decodificación

**Bloques:** Control Unit, Register File, `imm_gen` y sumador de `jal`.

- El **bus de instrucción** (`instrD`, la vertical gruesa) se reparte en campos:
  - `[6:0]` op, `[14:12]` funct3 y `[31:25]` funct7 → Control Unit;
  - `[19:15]` rs1 y `[24:20]` rs2 → puertos A1 y A2 del banco, y además viajan a ID/EX;
  - `[11:7]` rd → ID/EX (recién se usa en WB);
  - `[31:0]` → `imm_gen` y la copia `instr` para el snapshot.
- La **Control Unit** genera todas las señales de `tabla_control.md`. Algunas viajan por los latches (`reg_write`, `mem_write`, `alu_op`…) y otras se usan **acá mismo**:
  - `imm_type` → `imm_gen`;
  - `uses_rs1`, `uses_rs2`, `jump` y `halt` → Hazard Unit.
- El **Register File** tiene:
  - dos lecturas combinacionales (RD1, RD2);
  - una escritura en el flanco (A3/WD3/WE3, desde WB);
  - un tercer puerto de lectura para la Debug Unit (A4/RD4, naranja).

  Tiene **bypass**: si WB escribe el mismo registro que ID está leyendo, la lectura devuelve el valor nuevo.

- **`imm_gen`** reordena el inmediato según el formato (I/S/B/U/J) y lo extiende en signo. Es la fuente número uno de bugs: los formatos B y J tienen los bits mezclados.
- **Sumador de `jal`:** `pcD + immD` = `jal_target`. Si hay un `jal` válido en ID, la Hazard Unit pone `pc_sel = 01` y hace flush de IF/ID, porque la instrucción buscada detrás del `jal` no corresponde.

**ID/EX guarda:**

- datos: `pc`, `pc_plus4`, `rs1_data`, `rs2_data`, `imm`, `rs1`, `rs2`, `rd`, `funct3`, `funct7_b5`;
- control: `reg_write`, `mem_read`, `mem_write`, `result_src`, `alu_src`, `alu_op`, `branch`, `jump`, `jalr`;
- flags: `valid`, `halt`, `illegal`;
- copia de `instr`.

### 2.3 EX — ejecución

**Bloques:**

- muxes de forwarding A y B;
- mux `alu_src`;
- ALU con `alu_control`;
- `branch_cmp`;
- sumador de branch;
- `& ~1`;
- mux `ex_target`;
- bloque `redirect_ex`.

- **Forwarding (muxes de 3 entradas):** cada operando puede venir de:

  | `fwd` | Fuente                                  | Significa                                         |
  | ----- | --------------------------------------- | ------------------------------------------------- |
  | `00`  | `rs1_dataE` / `rs2_dataE` (leído en ID) | No hay dependencia cercana                        |
  | `01`  | `ResultW` (lo que se escribe en WB)     | El productor está 2 instrucciones atrás           |
  | `10`  | `alu_resultM`                           | El productor es la instrucción inmediata anterior |

- **`srcA`** va a la ALU y a `branch_cmp`.
- **El operando B forwardeado** va a tres lugares: al mux `alu_src`, a `branch_cmp` y a `store_data`. Por eso un `sw` cuyo dato se acaba de calcular funciona sin lógica extra.
- **`alu_src`** elige entre el registro y el inmediato.
- **`alu_control`** traduce `alu_op` + `funct3` + `funct7_b5` en `alu_ctrl[3:0]` (ADD, SUB, SLL, …, PASS_B).
- **Branches:**
  - `branch_cmp` calcula `eq = (A == B)`;
  - el sumador calcula `branch_target = pcE + immE`;
  - `redirect_ex` decide: `valid·(branch·(funct3==000 ? eq : !eq) + jalr)`.
- **`jalr`:** la ALU calcula `rs1 + imm`, se le aplica `& ~1` y se obtiene `jalr_target`. El mux `ex_target` (con selector `jalrE`) elige entre `jalr_target` y `branch_target`.
- Si `redirect_ex = 1`: `pc_sel = 10` y flush de IF/ID **e** ID/EX. Esas dos instrucciones se buscaron de más.

**EX/MEM guarda:**

- datos: `alu_result`, `store_data`, `pc_plus4`, `rd`, `funct3`;
- control: `reg_write`, `mem_read`, `mem_write`, `result_src`;
- flags: `valid`, `halt`, `illegal`;
- copia de `instr`.

### 2.4 MEM — memoria

**Bloques:** `store_align`, mux de escritura (núcleo / Debug Unit), Data Memory, bitmap de memoria usada y `load_extend`.

- La **dirección** es `alu_resultM`, y la DMEM la lee de forma combinacional.
- **`store_align`** usa `funct3` (sb/sh/sw) y `addr[1:0]` para ubicar el dato en el byte correcto y generar los byte-enables (`be`). La memoria es little-endian.
- **El mux de escritura** elige quién escribe:
  - el núcleo, cuando hay un store, con `mem_write·valid`;
  - la Debug Unit (`i_dbg_dmem_we`), que escribe ceros para limpiar la memoria, solo con el núcleo congelado.
- **El bitmap** marca qué palabras escribió el programa (solo los stores del núcleo), y el contador cuenta cuántas son. Así se arma el volcado de "memoria usada".
- **`load_extend`** usa `funct3` (lb/lh/lw/lbu/lhu) y `addr[1:0]` para extraer el byte o media palabra y extenderlo con signo o con ceros. El resultado es `mem_dataM`.
- **`alu_resultM`** también vuelve hacia atrás para el forwarding `10`.

**MEM/WB guarda:**

- datos: `alu_result`, `mem_data`, `pc_plus4`, `rd`;
- control: `reg_write`, `result_src`;
- flags: `valid`, `halt`, `illegal`;
- copia de `instr`.

### 2.5 WB — escritura

- El **mux de resultado** (`result_src`) elige qué se escribe en `rd`:
  - `00`: `alu_resultW`;
  - `01`: `mem_dataW` (loads);
  - `10`: `pc_plus4W` (`jal`/`jalr`).
- **`ResultW`** vuelve al banco (WD3) y a los forwarding `01`. **`rdW`** vuelve a A3, y **`reg_writeW·validW`** a WE3.
- **Fin de ejecución:** cuando llega a WB una instrucción con `halt·valid`, se activa `o_halted` (y además `o_illegal` si el flag `illegal` está en 1). En ese momento el pipeline está vacío.

### 2.6 Señales de control

Hay dos familias de señales de control. Conviene separarlas porque se generan en lugares distintos:

1. **Las del decodificador** (`control_unit`, en ID). Dependen solo de _qué instrucción es_ y viajan con ella por los latches.
2. **Las que coordinan el pipeline** (Hazard Unit, Forwarding Unit y Debug Unit). Dependen de _qué instrucciones conviven_ en el pipeline en ese ciclo.

La codificación exacta de cada una está en `docs/interfaces/tabla_control.md`.

#### 2.6.1 Señales del decodificador

**La idea clave: se decodifica una vez y la señal viaja.** La instrucción se decodifica **una sola vez, en ID**. Cada señal se sube al latch y "acompaña" a la instrucción hasta la etapa que la consume. Cuando la usó, se deja de propagar. Por eso los latches se van achicando hacia la derecha:

| Señal             | ID/EX | EX/MEM | MEM/WB | La consume                 |
| ----------------- | :---: | :----: | :----: | -------------------------- |
| `imm_type`        |       |        |        | ID mismo (`imm_gen`)       |
| `jump`            |  ✓\*  |        |        | ID (mux del PC)            |
| `uses_rs1/2`      |       |        |        | ID (Hazard Unit)           |
| `alu_src`         |   ✓   |        |        | EX                         |
| `alu_op`          |   ✓   |        |        | EX (`alu_control`)         |
| `branch`          |   ✓   |        |        | EX                         |
| `jalr`            |   ✓   |        |        | EX                         |
| `mem_read`        |   ✓   |  ✓\*   |        | EX (Hazard Unit, load-use) |
| `mem_write`       |   ✓   |   ✓    |        | MEM                        |
| `result_src`      |   ✓   |   ✓    |   ✓    | WB (y el forwarding)       |
| `reg_write`       |   ✓   |   ✓    |   ✓    | WB (y el forwarding)       |
| `halt`, `illegal` |   ✓   |   ✓    |   ✓    | WB → Debug Unit            |

\* `jumpE` y `mem_readM` están en los latches porque **los pide PRD §3.2**, que fija el contenido de cada latch. Pero el hardware ya no los usa en esa etapa: el `jal` ya redirigió en ID, y la DMEM se lee sola (es combinacional). Solo sirven para que el snapshot muestre qué tipo de instrucción hay en EX o en MEM. El snapshot vuelca **registros** (PC, banco, latches, memoria usada) más un byte con las salidas de la Hazard Unit y la Forwarding Unit en ese ciclo (`stall`, `flush_if_id`, `flush_id_ex`, `fwd_a`, `fwd_b`; ADR-017). La `control_unit` no se vuelca: su salida aparece un ciclo después, dentro de ID/EX.

Las que solo se usan en ID (`imm_type` y `uses_rs1/2`) no necesitan latch. `jump` tampoco, porque el `jal` redirige desde ID; solo viaja para el snapshot.

##### En ID

**`imm_type` (3 bits)** le dice a `imm_gen` cómo armar el inmediato de 32 bits a partir de la instrucción: I, S, B, U o J.

- **Por qué existe:** cada formato tiene el inmediato en bits distintos, partido y reordenado. Sin esta señal, `imm_gen` no sabe qué bits juntar.
- **Ejemplo:** en `sw x3, 4(x2)` el 4 está repartido entre `[31:25]` y `[11:7]`. Con `imm_type = 001` (S), `imm_gen` lo reconstruye.
- **Si está mal:** el inmediato sale con los bits cruzados, y el store va a otra dirección o el branch salta a cualquier lado.
- **Formato R:** no tiene inmediato, por eso figura "—".

**`jump` (1 bit)** vale 1 solo para `jal`.

- **Qué hace:** el destino `PC_ID + imm_J` se calcula en ID con un sumador propio, y la Hazard Unit pone `pc_sel = 01`.
- **Por qué en ID:** `jal` no depende de ningún registro, así que se puede resolver apenas se decodifica. Eso deja 1 ciclo de penalidad en vez de 2 (ADR-006).

**`uses_rs1` / `uses_rs2` (1 bit c/u)** dicen si la instrucción _de verdad_ lee ese registro. Solo los usa la Hazard Unit para detectar load-use.

- **Por qué existen:** los campos `rs1` y `rs2` siempre tienen bits, aunque la instrucción no los use. En `lui x5, 0x12345`, los bits que caen en el campo `rs1` son parte del inmediato.
- **Si no estuvieran:** un `lw x9, …` seguido de ese `lui` podría "coincidir" por casualidad y generar un **stall falso**.
- **Ejemplo:** en `addi`, `uses_rs2 = 0`, porque el campo `rs2` es parte del inmediato.

##### En EX

**`alu_src` (1 bit)** elige el operando B de la ALU: `0` = `rs2` (ya forwardeado), `1` = inmediato.

- **Ejemplos:** `add` → 0; `addi`, loads, stores, `jalr` y `lui` → 1.
- **Stores:** usan `alu_src = 1` porque la ALU calcula la dirección `rs1 + imm`. El `rs2` es el _dato_: pasa por al lado de la ALU, como `store_data`.

**`alu_op` (2 bits)** es una "pista" para `alu_control`. Con ella más `funct3` y `funct7[5]`, `alu_control` elige una de las 11 operaciones (`alu_ctrl[3:0]`, ADR-019).

| Valor | Significado  | Instrucciones                                               |
| ----- | ------------ | ----------------------------------------------------------- |
| `00`  | ADD fijo     | loads, stores, `jalr` (siempre suman una dirección)         |
| `01`  | PASS_B       | `lui`: deja pasar el inmediato. No hay mux en el operando A |
| `10`  | R-type       | mira `funct3` y `funct7[5]`                                 |
| `11`  | I aritmético | mira `funct3`; `funct7[5]` solo cuenta en los shifts        |

**Por qué `10` y `11` son distintos:** en `addi`, el bit 30 es parte del inmediato. Si se interpretara como `funct7[5]`, `addi x1, x1, -1024` haría una **resta**. Por eso, con `alu_op = 11` y `funct3 = 000`, siempre es ADD (US-201 AC2).

**`branch` (1 bit)** vale 1 para `beq` y `bne`.

- **Qué hace:** en EX, `branch_cmp` compara los operandos _forwardeados_ y, con `funct3`, decide si se toma: `000` = igual, `001` = distinto.
- **Si se toma:** `redirect_ex = 1`. La Hazard Unit pone `pc_sel = 10` y hace flush de IF/ID e ID/EX.
- **Por qué no usa la ALU:** la ALU podría estar ocupada calculando algo, y así el diseño queda más claro. Por eso `alu_op` es "—" para los branches.

**`jalr` (1 bit)** vale 1 solo para `jalr`.

- **Qué hace:** la ALU calcula `rs1 + imm`, se le aplica `& ~1` y el resultado va al PC.
- **Por qué está separado de `jump`:** se resuelve en **EX** y no en ID, porque necesita el valor de `rs1`, que puede venir por forwarding.
- **Selector del destino:** el mux `ex_target` elige entre el destino del branch (`PC_E + imm_B`) y el de `jalr`, usando `jalrE`.

**`mem_read` (1 bit)** marca los loads. Su uso funcional está **en EX**, en la Hazard Unit:

```verilog
stall = validE && mem_readE && rdE != 0 && ((uses_rs1D && rdE == rs1D) || (uses_rs2D && rdE == rs2D))
```

**Por qué hace falta:** el dato de un load recién existe al final de MEM. Ninguna otra instrucción tiene ese problema, porque todas tienen su resultado al final de EX y el forwarding las cubre (§4.3). Como la DMEM es de lectura combinacional (ADR-005), MEM no la necesita para leer.

##### En MEM

**`mem_write` (1 bit)** habilita la escritura en la DMEM.

- **Es la señal más peligrosa:** si se activa por error, rompe la memoria.
- **Siempre se combina con `valid`:** una burbuja o una instrucción descartada nunca escribe (R-EJ-6).
- **Bitmap de memoria usada:** también marca la palabra escrita en el bitmap (ADR-008).
- **Tamaño y alineación:** salen de `funct3` (`sb`/`sh`/`sw`), que viaja en el latch. Con eso, `store_align` arma los byte enables. No hay señal propia para el tamaño.

##### En WB

**`result_src` (2 bits)** elige qué se escribe en `rd`:

| Valor | Fuente                                                | Instrucciones                        |
| ----- | ----------------------------------------------------- | ------------------------------------ |
| `00`  | resultado de la ALU                                   | aritméticas, lógicas, `lui`          |
| `01`  | dato leído de memoria, ya extendido por `load_extend` | loads                                |
| `10`  | `PC+4`                                                | `jal`, `jalr` (dirección de retorno) |

**Ejemplo:** `jal x1, f` escribe `PC+4` en `x1`, no lo que calcule la ALU.

**`reg_write` (1 bit)** habilita la escritura de `rd` en el banco.

- **La usan también los forwarders:** solo se forwardea desde una etapa si `reg_write = 1`, `valid = 1` y `rd ≠ 0`. Un `sw` que está en MEM tiene un "`rd`" (son bits del inmediato), pero como `reg_write = 0`, no se forwardea basura.

**`halt` / `illegal` (1 bit c/u):**

- **`halt` en ID** activa `halt_fetch`: el PC se congela y entran burbujas a IF/ID.
- **Después viajan hasta WB.** Cuando el HALT llega a WB, todo lo anterior ya terminó, y el núcleo activa `o_halted`.
- **`illegal`** solo distingue el motivo de la terminación: `HALTED` o `ILLEGAL` (ADR-018).
- **Ninguna de las dos escribe nada:** `reg_write = mem_write = 0`.

#### 2.6.2 Señales que coordinan el pipeline

Estas no dependen de una instrucción sola, sino de la relación entre instrucciones en distintas etapas. Se ven en detalle en las secciones 4, 5 y 6.

| Señal                          | La genera       | Qué hace                                                                                                                                                                                                              |
| ------------------------------ | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`valid`** (1 por latch)      | cada etapa      | Dice si en ese latch hay una instrucción real o una burbuja. Todo efecto (escribir registro o memoria, forwardear, pedir stall, terminar) se condiciona con `valid`. Un flush **no borra** el latch: pone `valid = 0` |
| **`fwd_a` / `fwd_b`** (2 bits) | Forwarding Unit | Elige de dónde salen los operandos en EX: `00` = banco (vía ID/EX), `10` = EX/MEM (distancia 1), `01` = MEM/WB (distancia 2). EX/MEM tiene prioridad porque es el valor más nuevo                                     |
| **`StallF`**                   | Hazard Unit     | Congela el PC: `stall \| halt_fetch \| i_stop_fetch`                                                                                                                                                                  |
| **`StallD`**                   | Hazard Unit     | Congela IF/ID: la instrucción en ID repite el ciclo (load-use)                                                                                                                                                        |
| **`FlushD`**                   | Hazard Unit     | Burbuja en IF/ID: descarta lo que estaba en IF. Se activa con un `jal` en ID o una redirección desde EX                                                                                                               |
| **`FlushE`**                   | Hazard Unit     | Burbuja en ID/EX: por load-use (no se manda a EX una instrucción sin su dato) o por redirección desde EX (lo que estaba en ID era especulativo)                                                                       |
| **`pc_sel`** (2 bits)          | Hazard Unit     | Mux del PC: `00` = `PC+4` · `01` = destino de `jal` (ID) · `10` = destino de EX (branch o `jalr`). Prioridad: EX > `jal` > stall > HALT (§5.2)                                                                        |
| **`halt_fetch`**               | ID              | Un HALT o una instrucción ilegal en ID detienen la búsqueda. Se cancela si EX redirige, porque entonces el HALT era especulativo (R-EJ-4)                                                                             |

**Señales que vienen de la Debug Unit** (ADR-001, 009 y 010; ver §7):

- **`i_enable`:** _clock enable_ de todo el núcleo. Con 0, nada cambia. Un STEP es exactamente 1 ciclo con `i_enable = 1`.
- **`i_stop_fetch`** (ABORT): hace lo mismo que el HALT, pero se pide desde afuera. Congela el PC y deja que el pipeline se vacíe.
- **`i_flush_all`:** reset del pipeline. Pone `valid = 0` en los 4 latches, y el PC y los registros en 0.

#### 2.6.3 Cómo encaja todo, con un ejemplo

```asm
lw  x1, 0(x2)
add x3, x1, x4
```

1. **Ciclo en que `lw` está en EX y `add` en ID:**
   - el `lw` llega con `mem_readE = 1` y `rdE = x1`;
   - el `add` tiene `uses_rs1D = 1` y `rs1D = x1`;
   - la Hazard Unit pone `stall = 1`, y con eso `StallF = StallD = FlushE = 1`.
2. **Ciclo siguiente:** el `add` repite ID y entra una burbuja a EX (`validE = 0`). El `lw` pasa a MEM.
3. **Ciclo siguiente:** el `add` llega a EX con el `lw` ya en WB, y la Forwarding Unit pone `fwd_a = 01`. En ese mismo ciclo, el `lw` escribe con `reg_write = 1` y `result_src = 01`.

**Para la defensa,** cada señal se explica en tres partes:

- **quién la genera y dónde;**
- **qué elige o habilita;**
- **qué se rompe si estuviera mal.**

---

## 3. El camino de cada tipo de instrucción

### 3.0 Qué hace cada instrucción (33 instrucciones en total)

La codificación binaria está en PRD 2.2 y las señales de control en `tabla_control.md`. Esta tabla explica **qué hace** cada instrucción, con un ejemplo con valores.

Convenciones:

- `imm` es el inmediato ya extendido en signo a 32 bits.
- Los ejemplos usan valores en hexadecimal donde importa el signo.
- Toda la aritmética es **módulo 2³²**: no hay excepciones por overflow (`0x7FFFFFFF + 1 = 0x80000000`).

#### Aritméticas y lógicas entre registros (tipo R)

| #   | Instrucción         | Qué hace                                                          | Ejemplo                            | Para qué se usa / detalle                                      |
| --- | ------------------- | ----------------------------------------------------------------- | ---------------------------------- | -------------------------------------------------------------- |
| 1   | `add rd, rs1, rs2`  | `rd = rs1 + rs2`                                                  | x1=5, x2=3 → `add x3,x1,x2` → x3=8 | Suma. Con `rs2 = x0` copia un registro (eso es la pseudo `mv`) |
| 2   | `sub rd, rs1, rs2`  | `rd = rs1 − rs2`                                                  | x1=5, x2=7 → x3=−2 (`0xFFFFFFFE`)  | `sub rd, x0, rs` = negar un número                             |
| 3   | `sll rd, rs1, rs2`  | Desplaza `rs1` a la izquierda `rs2[4:0]` posiciones; entran ceros | x1=1, x2=4 → x3=16                 | Multiplicar por 2ⁿ. Solo cuentan 5 bits: con x2=33 desplaza 1  |
| 4   | `slt rd, rs1, rs2`  | `rd = 1` si `rs1 < rs2` **con signo**, si no `0`                  | x1=−1, x2=1 → x3=1                 | Comparar enteros con signo                                     |
| 5   | `sltu rd, rs1, rs2` | `rd = 1` si `rs1 < rs2` **sin signo**, si no `0`                  | x1=−1 (`0xFFFFFFFF`), x2=1 → x3=0  | Comparar direcciones. `sltu rd, x0, rs` → `rd = (rs ≠ 0)`      |
| 6   | `xor rd, rs1, rs2`  | OR exclusivo bit a bit                                            | `0b1100 ^ 0b1010` = `0b0110`       | Invertir bits seleccionados; `xor rd, rs, rs` da 0             |
| 7   | `srl rd, rs1, rs2`  | Desplaza a la derecha **lógico**: entran ceros                    | `0x80000000 >> 4` = `0x08000000`   | Dividir por 2ⁿ números sin signo; extraer campos               |
| 8   | `sra rd, rs1, rs2`  | Desplaza a la derecha **aritmético**: se replica el bit de signo  | `0x80000000 >>> 4` = `0xF8000000`  | Dividir por 2ⁿ números con signo (redondea hacia −∞)           |
| 9   | `or rd, rs1, rs2`   | OR bit a bit                                                      | `0b1100 \| 0b1010` = `0b1110`      | Encender bits                                                  |
| 10  | `and rd, rs1, rs2`  | AND bit a bit                                                     | `0b1100 & 0b1010` = `0b1000`       | Aplicar máscaras (apagar bits)                                 |

#### Aritméticas y lógicas con inmediato (tipo I)

El inmediato es de 12 bits con signo: va de −2048 a 2047.

| #   | Instrucción           | Qué hace                                                                                            | Ejemplo                                                | Para qué se usa / detalle                                                              |
| --- | --------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| 11  | `addi rd, rs1, imm`   | `rd = rs1 + imm`                                                                                    | `addi x1, x0, 5` → x1 = x0 + 5 = 5 (x0 vale siempre 0) | Cargar constantes chicas, sumar offsets. `addi x0,x0,0` = `nop`; `addi rd,rs,0` = `mv` |
| 12  | `slti rd, rs1, imm`   | `rd = 1` si `rs1 < imm` con signo                                                                   | x1=−3 → `slti x2,x1,0` → x2=1                          | "¿es negativo?"                                                                        |
| 13  | `sltiu rd, rs1, imm`  | `rd = 1` si `rs1 < imm` sin signo (el imm **se extiende con signo** y después se compara sin signo) | `sltiu x2,x1,1` → x2 = (x1 == 0)                       | Comparar contra cero. Ojo: `imm = −1` se compara como `0xFFFFFFFF`                     |
| 14  | `xori rd, rs1, imm`   | `rd = rs1 ^ imm`                                                                                    | `xori x2,x1,−1` → x2 = NOT x1                          | Negación bit a bit                                                                     |
| 15  | `ori rd, rs1, imm`    | `rd = rs1 \| imm`                                                                                   | `ori x2,x1,1` → enciende el bit 0                      | Encender bits                                                                          |
| 16  | `andi rd, rs1, imm`   | `rd = rs1 & imm`                                                                                    | `andi x2,x1,0xFF` → byte bajo de x1                    | Máscaras                                                                               |
| 17  | `slli rd, rs1, shamt` | `rd = rs1 << shamt` (shamt de 0 a 31, va en el campo del inmediato)                                 | `slli x2,x1,2` → x2 = x1·4                             | Multiplicar por 2ⁿ (por ejemplo, índice → offset de palabra)                           |
| 18  | `srli rd, rs1, shamt` | Desplazamiento lógico a la derecha                                                                  | `srli x2,x1,24` → byte alto de x1                      | `funct7 = 0000000` la distingue de `srai`                                              |
| 19  | `srai rd, rs1, shamt` | Desplazamiento aritmético a la derecha                                                              | x1=−16 → `srai x2,x1,2` → x2=−4                        | `funct7 = 0100000` (bit 30 = 1)                                                        |

#### Loads (tipo I)

Dirección = `rs1 + imm`. La memoria es little-endian: el byte de dirección más baja es el menos significativo. Los accesos desalineados ignoran los bits bajos.

| #   | Instrucción        | Qué hace                                 | Ejemplo (en memoria: `M[0x10] = 0x80`, `M[0x20..0x21] = 0x8000`) | Detalle                                                 |
| --- | ------------------ | ---------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------- |
| 20  | `lb rd, imm(rs1)`  | Carga 1 byte y lo **extiende con signo** | `lb x2, 0x10(x0)` → x2 = `0xFFFFFF80`                            | Para `char` con signo                                   |
| 21  | `lh rd, imm(rs1)`  | Carga 2 bytes y los extiende con signo   | `lh x2, 0x20(x0)` → x2 = `0xFFFF8000`                            | Ignora `addr[0]`                                        |
| 22  | `lw rd, imm(rs1)`  | Carga una palabra de 4 bytes             | `lw x2, 8(x1)` → x2 = M[x1+8]                                    | Ignora `addr[1:0]`. Puede provocar un stall de load-use |
| 23  | `lbu rd, imm(rs1)` | Carga 1 byte y lo **extiende con ceros** | `lbu x2, 0x10(x0)` → x2 = `0x00000080`                           | Para bytes sin signo                                    |
| 24  | `lhu rd, imm(rs1)` | Carga 2 bytes y los extiende con ceros   | `lhu x2, 0x20(x0)` → x2 = `0x00008000`                           | Ignora `addr[0]`                                        |

#### Stores (tipo S)

Dirección = `rs1 + imm`. Se guardan los bits **bajos** de `rs2`. No escriben ningún registro.

| #   | Instrucción        | Qué hace                      | Ejemplo (x2 = `0x12345678`)                                     | Detalle                                                            |
| --- | ------------------ | ----------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------ |
| 26  | `sb rs2, imm(rs1)` | `M[addr] = rs2[7:0]`          | `sb x2, 0(x1)` → escribe `0x78`; los otros 3 bytes no cambian   | Usa byte-enables (`store_align`)                                   |
| 27  | `sh rs2, imm(rs1)` | `M[addr..addr+1] = rs2[15:0]` | `sh x2, 0(x1)` → escribe `0x5678`                               | Ignora `addr[0]`                                                   |
| 28  | `sw rs2, imm(rs1)` | `M[addr..addr+3] = rs2`       | `sw x2, 0(x1)` → en memoria queda `78 56 34 12` (little-endian) | Ignora `addr[1:0]`. Marca la palabra en el bitmap de memoria usada |

#### Saltos y branches

El destino de `beq`, `bne` y `jal` es **relativo al PC de la propia instrucción**: el ensamblador calcula `imm = etiqueta − PC`. Siempre es múltiplo de 2.

| #   | Instrucción          | Qué hace                                                             | Ejemplo                                                  | Detalle                                                                      |
| --- | -------------------- | -------------------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 29  | `beq rs1, rs2, etiq` | Si `rs1 == rs2`, salta a `PC + imm`; si no, sigue en `PC + 4`        | `beq x1, x0, fin` → salta si x1 = 0                      | Alcance ±4 KiB. Se resuelve en EX: si se toma, cuesta 2 ciclos               |
| 30  | `bne rs1, rs2, etiq` | Si `rs1 ≠ rs2`, salta                                                | `bne x1, x2, loop` → repite mientras x1 ≠ x2             | Es la base de los loops con contador                                         |
| 31  | `lui rd, imm20`      | `rd = imm20 << 12`: carga los 20 bits altos y pone en 0 los 12 bajos | `lui x1, 0x12345` → x1 = `0x12345000`                    | Con `addi` arma constantes de 32 bits (ver abajo)                            |
| 32  | `jal rd, etiq`       | `rd = PC + 4` y salta a `PC + imm`                                   | `jal x1, funcion` → llamada a subrutina                  | Alcance ±1 MiB. Se resuelve en ID (1 ciclo). `jal x0, etiq` = pseudo `j`     |
| 25  | `jalr rd, imm(rs1)`  | `rd = PC + 4` y salta a `(rs1 + imm) & ~1`                           | `jalr x0, 0(x1)` → vuelve de la subrutina (pseudo `ret`) | Salto a una dirección calculada en un registro. Se resuelve en EX (2 ciclos) |

`lui` no es un salto, pero va acá porque es tipo U (Upper), como el inmediato de `jal`.

#### Propia del proyecto

| #   | Instrucción | Qué hace                                                                                                        | Detalle                                                                                        |
| --- | ----------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 33  | `halt`      | Detiene la búsqueda de instrucciones; las anteriores terminan y la ejecución finaliza cuando el HALT llega a WB | Opcode _custom-0_ (`0x0000000B`). No escribe nada. El ensamblador agrega uno al final si falta |

#### pseudoinstrucciones

El ensamblador solo soporta las pseudoinstrucciones `nop`, `mv`, `j` y `ret`. El resto se escribe con la instrucción real:

| Quiero…                           | Se escribe                                |
| --------------------------------- | ----------------------------------------- |
| No hacer nada                     | `nop` = `addi x0, x0, 0`                  |
| Copiar un registro                | `mv rd, rs` = `addi rd, rs, 0`            |
| Cargar una constante chica        | `addi rd, x0, 100` (de −2048 a 2047)      |
| Cargar una constante de 32 bits   | `lui rd, alto` + `addi rd, rd, bajo` (\*) |
| Negar (cambiar de signo)          | `sub rd, x0, rs`                          |
| NOT bit a bit                     | `xori rd, rs, -1`                         |
| `rd = (rs == 0)`                  | `sltiu rd, rs, 1`                         |
| `rd = (rs ≠ 0)`                   | `sltu rd, x0, rs`                         |
| Salto incondicional               | `j etiq` = `jal x0, etiq`                 |
| Llamar a una subrutina            | `jal x1, funcion`                         |
| Volver de una subrutina           | `ret` = `jalr x0, 0(x1)`                  |
| Saltar si es cero / si no es cero | `beq rs, x0, etiq` / `bne rs, x0, etiq`   |

(\*) **Trampa de `lui` + `addi`:** el `addi` extiende su inmediato con signo. Si el bit 11 de la parte baja vale 1, el `addi` resta, y hay que sumarle 1 a la parte alta. Ejemplo para `0x12345FFF`: `lui x1, 0x12346` + `addi x1, x1, -1`, y no `lui x1, 0x12345` + `addi x1, x1, 0xFFF` (eso no entra en 12 bits con signo).

#### Instrucciones de RV32I que **no** están implementadas

`auipc`, `blt`, `bge`, `bltu`, `bgeu`, `fence`, `ecall`, `ebreak` y las extensiones (M, etc.). Si aparecen en un programa, el procesador las trata como **ilegales** y termina con estado `ILLEGAL`. Para comparar por menor o mayor se usa `slt`/`sltu` + `bne`/`beq`.

### 3.1 Recorrido de cada tipo por el datapath

Para cada una, seguí el recorrido en el diagrama. Las señales son las de `tabla_control.md`.

#### `add x3, x1, x2` (tipo R)

`reg_write=1`, `alu_src=0`, `alu_op=10`, `result_src=00`.

IF busca → ID lee x1 y x2 → EX: la ALU suma `srcA + srcB` (srcB = registro) → MEM: no toca la memoria, el resultado solo la atraviesa → WB: `alu_resultW` va a x3.

#### `addi x3, x1, -4` (tipo I)

Igual que `add`, pero con `alu_src=1` (operando B = inmediato) y `alu_op=11`.

**Trampa:** el bit 30 de la instrucción es parte del inmediato, no `funct7`. Si `alu_control` lo mirara para `addi`, un inmediato negativo convertiría la suma en una resta. Por eso con `alu_op=11` el bit 30 solo se mira cuando `funct3=101` (para distinguir `srli` de `srai`).

#### `lw x2, 8(x1)` (load)

`mem_read=1`, `reg_write=1`, `alu_src=1`, `alu_op=00` (ADD), `result_src=01`.

EX: la ALU calcula la dirección `x1 + 8` → MEM: la DMEM lee y `load_extend` arma el dato → WB: `mem_dataW` va a x2.

**El dato recién existe al final de MEM.** Por eso la instrucción siguiente no lo puede recibir a tiempo en EX: es el load-use (sección 4.3).

#### `sw x2, 8(x1)` (store)

`mem_write=1`, `reg_write=0`, `alu_src=1`, `alu_op=00`, `imm_type=S`, `uses_rs2=1`.

EX: la ALU calcula la dirección, y el dato (x2 forwardeado) viaja como `store_data` → MEM: `store_align` + escritura + marca en el bitmap → WB: no hace nada.

#### `beq x1, x2, etiqueta` (branch)

`branch=1`, `imm_type=B`. **No usa la ALU.**

EX: `branch_cmp` compara los operandos forwardeados y el sumador calcula `pcE + immE`. Si se toma el salto: redirección + flush de IF/ID e ID/EX (**2 ciclos de penalidad**). Si no se toma, no hay penalidad.

`bne` es igual, con la condición negada: `funct3 = 001`.

#### `jal x1, etiqueta`

`jump=1`, `reg_write=1`, `result_src=10`, `imm_type=J`.

ID: el sumador calcula `pcD + immD`, el PC se redirige y se hace flush de IF/ID (**1 ciclo**). Después la instrucción sigue su camino normal para escribir `pc_plus4` en `x1` en WB.

#### `jalr x0, 0(x1)` (por ejemplo, `ret`)

`jalr=1`, `reg_write=1`, `result_src=10`, `alu_src=1`, `alu_op=00`.

EX: la ALU calcula `x1 + 0`, se le aplica `& ~1`, se redirige el PC y se hace flush de 2 instrucciones. En WB se escribe `pc_plus4` en rd (acá x0, así que no tiene efecto).

**Por qué se resuelve en EX y no en ID:** depende de un registro que podría estar recién calculado, y el forwarding llega a EX, no a ID.

#### `lui x5, 0x12345`

`reg_write=1`, `alu_src=1`, `alu_op=01` (PASS_B), `imm_type=U`, `uses_rs1=0`.

`imm_gen` ya entrega `0x12345000`, y la ALU lo deja pasar tal cual. No lee registros: el campo rs1 tiene "basura" que **no debe** provocar stalls. Para eso sirve `uses_rs1`.

#### `halt`

`halt=1` y ninguna escritura. Ver la sección 6.

---

## 4. Riesgos de datos

### 4.1 El problema

```asm
add x1, x2, x3     # escribe x1 en WB (ciclo 5)
sub x4, x1, x5     # necesita x1 en EX (ciclo 4)  ← todavía no está en el banco
```

### 4.2 Forwarding (Forwarding Unit, en EX)

Condición para el operando A. La del B es igual, cambiando `rs1E` por `rs2E`:

```txt
si   EX/MEM.reg_write && EX/MEM.valid && rdM != 0 && rdM == rs1E   → fwd_a = 10
sino MEM/WB.reg_write && MEM/WB.valid && rdW != 0 && rdW == rs1E   → fwd_a = 01
sino                                                               → fwd_a = 00
```

Tres detalles para la defensa:

1. **EX/MEM tiene prioridad** sobre MEM/WB, porque tiene el valor más reciente. Ejemplo: `add x1,..` / `add x1,..` / `sub x2,x1,..` → tiene que usar el segundo `add`.
2. **Nunca se forwardea x0**, aunque una instrucción "escriba" x0 (como `jalr x0, 0(x1)`), porque x0 vale siempre 0.
3. **Nunca se forwardea desde una burbuja** (`valid=0`): podría tener basura en `rd`.

### 4.3 Load-use: el único stall (Hazard Unit, en ID)

```asm
lw  x1, 0(x2)
add x3, x1, x4     # en EX necesita x1, pero lw recién lo tiene al final de MEM
```

Condición, evaluada con `lw` en EX y `add` en ID:

```verilog
stall = validE && mem_readE && rdE != 0 &&
        ((uses_rs1D && rdE == rs1D) || (uses_rs2D && rdE == rs2D))
```

Efecto, durante 1 ciclo:

- **PC e IF/ID se congelan** (`StallF`, `StallD`): la instrucción se repite;
- **ID/EX recibe una burbuja** (`FlushE`).

En el ciclo siguiente el `lw` está en WB y el dato llega por forwarding `01`.

Casos borde:

- `lw x1` seguido de una instrucción independiente y después `add x3, x1` → **0 stalls**: forwarding desde MEM/WB.
- `lw x1` seguido de `lui x1` → **0 stalls**: `lui` no lee rs1.
- `lw x1` seguido de `sw x1, 0(x2)` → **1 stall**: no hay forwarding de MEM a MEM.

### 4.4 bypass del banco (wb → id)

si en el mismo ciclo wb escribe x5 e id lee x5, el banco devuelve el valor que se está escribiendo. así cubre la distancia 3, que el forwarding no alcanza. el libro lo resuelve escribiendo en el flanco de bajada. este diseño no, porque usa un solo flanco.

### 4.5 Resumen por distancia

| Distancia productor → consumidor | Productor ALU       | Productor load                |
| -------------------------------- | ------------------- | ----------------------------- |
| 1 (inmediatamente después)       | forwarding `10`     | **1 stall** + forwarding `01` |
| 2                                | forwarding `01`     | forwarding `01`               |
| 3                                | bypass del banco    | bypass del banco              |
| ≥ 4                              | ya está en el banco | ya está en el banco           |

---

## 5. Riesgos de control

### 5.1 Los dos puntos de redirección

| Dónde | Instrucciones               | Destino                         | Se descartan                              | Penalidad |
| ----- | --------------------------- | ------------------------------- | ----------------------------------------- | --------- |
| ID    | `jal`                       | `pcD + immJ`                    | la de IF (flush IF/ID)                    | 1 ciclo   |
| EX    | `beq`/`bne` tomados, `jalr` | `pcE + immB` / `(rs1+imm) & ~1` | la de IF y la de ID (flush IF/ID + ID/EX) | 2 ciclos  |

Un branch **no tomado** cuesta 0 ciclos: se predice siempre "no tomado", porque IF sigue buscando `PC + 4`.

### 5.2 Prioridades en un mismo ciclo

1. **Redirección desde EX:** es la instrucción más vieja, así que todo lo que hay detrás es especulativo.
2. `jal` en ID.
3. Stall de load-use.
4. HALT o ilegal detectado en ID.

Ejemplo: `beq` tomado en EX y `jal` en ID en el mismo ciclo. Gana el `beq`, y el `jal` se descarta porque nunca debió ejecutarse.

Ejemplo: branch tomado en EX mientras ID pide stall de load-use. Gana el flush: la instrucción que pedía el stall estaba en el camino equivocado.

---

## 6. HALT, instrucciones ilegales y drenado

### 6.1 HALT

1. **En ID** se detecta el opcode `0001011`. Se activa `halt_fetch`: el PC se congela y a IF/ID entran burbujas.
2. **El HALT sigue avanzando** marcado con `halt=1`, sin escribir nada.
3. **Las instrucciones anteriores al HALT** terminan normalmente.
4. **Cuando el HALT llega a WB**, todas las anteriores ya terminaron y detrás no hay nada. El pipeline está vacío y se activa `o_halted`.

**HALT especulativo (R-EJ-4):** si el HALT quedó en IF/ID o ID/EX cuando un branch más viejo redirige, se descarta con el flush y la ejecución continúa en el destino del salto.

### 6.2 Instrucción ilegal

Funciona igual que el HALT, pero con `illegal=1`. Al llegar a WB activa `o_halted` y además `o_illegal`, y el estado final es `ILLEGAL`.

Una palabra ilegal buscada especulativamente detrás de un salto tomado **no detiene nada**: se descarta con el flush.

Pregunta típica: `0x00000000` es ilegal, no es un NOP. Por eso ejecutar memoria vacía termina en `ILLEGAL`.

### 6.3 ABORT (`i_stop_fetch`)

Mientras está activo: el PC se congela y IF/ID e ID/EX reciben burbujas, así que la instrucción que estaba en ID también se descarta. Lo que ya estaba en EX, MEM y WB termina normalmente.

---

## 7. Debug Unit, `i_enable` y valid

- **`i_enable`** congela el núcleo entero: PC, latches, escritura del banco, DMEM y bitmap. **No se dibuja en cada registro** (lo aclara la leyenda).
  - **STEP** = un ciclo con `i_enable=1`;
  - **RUN** = `i_enable=1` sostenido.
- **Puertos naranjas:** solo los usa la Debug Unit, y siempre con el núcleo congelado:
  - escribir la IMEM (LOAD);
  - limpiar la DMEM (escribe ceros sin marcar el bitmap);
  - leer registros (A4/RD4);
  - leer la DMEM (A2/RD2);
  - leer el bitmap y el contador.
- **Salidas para el snapshot:** `o_pc`, los 4 latches como buses planos (`riscv_core.md` §4), `o_stall`, `o_flush_*` y `o_fwd_*`. Con esas señales la GUI muestra **dónde actuó cada mecanismo**.
- **`valid`:** distingue una burbuja de una instrucción real. Sin él, un flush sería indistinguible de un `addi x0,x0,0`, y no se podría afirmar que "el pipeline está vacío". Toda escritura (`reg_write`, `mem_write`) se condiciona con `valid`.

---

## 8. Ejemplo resuelto ciclo a ciclo

Programa (la DMEM arranca en 0):

```txt
0x00  addi x1, x0, 8
0x04  lw   x2, 0(x1)       # x2 = M[8]
0x08  add  x3, x2, x1      # load-use con lw  → 1 stall
0x0C  sub  x4, x3, x1      # usa x3 del add anterior → forwarding EX/MEM
0x10  beq  x4, x4, +12     # siempre tomado → salta a 0x1C; x4 viene por forwarding
0x14  addi x5, x0, 1       # se busca de más → flush
0x18  addi x6, x0, 2       # se busca de más → flush
0x1C  halt
```

Carta de pipeline. "—" = burbuja (`valid=0`).

| Ciclo | IF      | ID      | EX   | MEM  | WB   | Qué pasa                                                                                                              |
| ----- | ------- | ------- | ---- | ---- | ---- | --------------------------------------------------------------------------------------------------------------------- |
| 1     | addi    | —       | —    | —    | —    |                                                                                                                       |
| 2     | lw      | addi    | —    | —    | —    |                                                                                                                       |
| 3     | add     | lw      | addi | —    | —    |                                                                                                                       |
| 4     | sub     | add     | lw   | addi | —    | **Stall:** `lw` en EX (`mem_readE`, `rdE=x2`) y `add` en ID lee x2. PC e IF/ID se congelan; burbuja a ID/EX           |
| 5     | sub     | add     | —    | lw   | addi | `add` repite ID. `addi` escribe x1 en WB y `add` lee x1 en ID en el mismo ciclo → **bypass del banco**                |
| 6     | beq     | sub     | add  | —    | lw   | `add` en EX: x2 viene de MEM/WB (`lw`) → **`fwd_a = 01`**; x1 ya venía bien de ID → `fwd_b = 00`                      |
| 7     | addi x5 | beq     | sub  | add  | —    | `sub` en EX: x3 viene de EX/MEM (`add`) → **`fwd_a = 10`**                                                            |
| 8     | addi x6 | addi x5 | beq  | sub  | add  | `beq` en EX: x4 viene de EX/MEM (`sub`) → `fwd_a = fwd_b = 10`; `eq=1` → **tomado**: `pc_sel=10`, flush IF/ID e ID/EX |
| 9     | halt    | —       | —    | beq  | sub  | Las dos instrucciones buscadas de más se convirtieron en burbujas                                                     |
| 10    | (0x20)  | halt    | —    | —    | beq  | **HALT detectado en ID:** PC congelado; lo buscado en IF se descarta                                                  |
| 11    | —       | —       | halt | —    | —    | El HALT avanza                                                                                                        |
| 12    | —       | —       | —    | halt | —    |                                                                                                                       |
| 13    | —       | —       | —    | —    | halt | **HALT en WB → `o_halted = 1`**; el pipeline queda vacío                                                              |

**Cuenta de ciclos:**

- Se ejecutaron 6 instrucciones útiles (addi, lw, add, sub, beq, halt).
- Sin riesgos serían 6 + 4 = 10 ciclos (4 de llenado).
- Se sumaron 1 stall de load-use y 2 de flush del branch: 10 + 1 + 2 = **13 ciclos**.

**Para practicar:**

1. Cambiá el `beq` por `bne x4, x4, +12`: no se toma. ¿Cuántos ciclos tarda y qué instrucciones se ejecutan?
2. Poné un `jal x0, +8` en 0x14. ¿Cambia algo? Pista: nunca llega a ID porque se descarta antes.
3. Insertá una instrucción independiente entre `lw` y `add`. ¿Desaparece el stall? ¿Qué `fwd_a` tiene ahora el `add`?
4. Armá tu programa de 10 instrucciones para cumplir con la US-103 AC4. Tiene que incluir: un load-use, un forwarding EX/MEM y un `beq` tomado.

---

## 9. Errores típicos (y cómo los vas a reconocer)

| Error                                        | Síntoma                                                                      |
| -------------------------------------------- | ---------------------------------------------------------------------------- |
| `imm_gen` mal en el formato B o J            | Los saltos van a destinos absurdos o con offsets impares                     |
| `alu_control` mira `funct7` en `addi`        | `addi x1, x0, -1024` resta en lugar de sumar                                 |
| Forwarding sin chequear `rd != 0`            | Un `jalr x0, ...` "contamina" el operando de la instrucción siguiente        |
| Forwarding o escrituras sin chequear `valid` | Una burbuja con basura escribe registros o memoria                           |
| Stall sin `uses_rs1`/`uses_rs2`              | Stalls falsos con `lui` o `jal` detrás de un `lw`                            |
| Prioridad mal entre flush de EX y stall      | Un branch tomado mientras hay load-use ejecuta la instrucción equivocada     |
| HALT que no se descarta con el flush         | El programa termina antes de tiempo si hay un HALT detrás de un `beq` tomado |
| Algún registro que no respeta `i_enable`     | El modo paso a paso da un resultado distinto que RUN (R-EJ-7)                |

---

## 10. Preguntas de autoevaluación

Respondé sin mirar y después abrí la respuesta.

- **¿Por qué hay un latch entre cada par de etapas y qué pasaría sin ellos?**

Cada etapa trabaja sobre una instrucción distinta. El latch guarda, al final del ciclo, todo lo que la instrucción necesita en las etapas siguientes. Sin latches, las señales de una instrucción se mezclarían con las de la siguiente y el diseño sería combinacional de punta a punta, como un procesador uniciclo.

- **¿Por qué rd viaja hasta WB si se decodifica en ID?**

Porque recién en WB se sabe el resultado y se escribe el banco. Si se usara `rd` directamente desde ID, se escribiría el registro destino de la instrucción que está en ID en ese momento, que es otra (3 instrucciones más nueva).

- **¿Por qué el forwarding desde EX/MEM tiene prioridad sobre MEM/WB?**

Si las dos instrucciones escriben el mismo registro, la de EX/MEM es la más reciente en el orden del programa, así que su valor es el correcto.

- **¿Por qué el load-use necesita un stall y no se resuelve con forwarding?**

El dato del load recién existe al final de MEM. La instrucción siguiente lo necesita al principio de EX, en ese mismo ciclo. No se puede adelantar un dato que todavía no existe: hay que esperar un ciclo y forwardearlo desde MEM/WB.

- **¿Por qué jal se resuelve en ID pero jalr en EX?**

`jal` solo depende de `PC + inmediato`, que se conocen en ID, así que se resuelve antes y cuesta 1 ciclo. `jalr` depende de `rs1`, que puede venir de una instrucción anterior todavía en vuelo. El forwarding llega a EX, no a ID, y resolverlo en ID exigiría forwarding hacia ID y stalls nuevos.

- **¿Qué hace el bit `valid` y qué pasaría si no existiera?**

Marca si el contenido del latch es una instrucción real o una burbuja. Todas las escrituras y el forwarding se condicionan con él. Sin `valid`, una burbuja no se distinguiría de una instrucción, el flush tendría que convertir la instrucción en un NOP real, y no se podría saber cuándo el pipeline está vacío para el HALT.

Un `sw x5, 0(x6)` justo después de `add x5, ...`: ¿de dónde sale el dato que se guarda?

Del forwarding `10` sobre el operando B. El valor forwardeado alimenta tanto el mux `alu_src` como `store_data`, que viaja a MEM por EX/MEM.

- **¿Qué pasa si hay un HALT inmediatamente después de un beq tomado?**

El HALT se detecta en ID mientras el `beq` está en EX. En ese mismo ciclo el `beq` redirige, y la redirección desde EX tiene prioridad: el HALT se descarta con el flush de IF/ID e ID/EX, `halt_fetch` se desactiva y la ejecución sigue en el destino (R-EJ-4).

- **¿Por qué hay un mux en el puerto de escritura de la DMEM?**

La memoria distribuida tiene un solo puerto de escritura. Lo usan el núcleo (stores) y la Debug Unit (limpieza a cero en LOAD/RESET). La Debug Unit solo escribe con el núcleo congelado, así que nunca hay conflicto real.

- **¿Por qué `lui` no genera stall detrás de un `lw` aunque su campo rs1 coincida con el rd del load?**

Porque `uses_rs1 = 0` para `lui`. La Hazard Unit solo compara los registros que la instrucción realmente lee. Sin esa bandera habría stalls falsos.

- **¿Cuántos ciclos tarda en total un programa de N instrucciones sin riesgos?**

N + 4: 4 ciclos para llenar el pipeline, y después termina una instrucción por ciclo (CPI → 1). Cada stall suma 1, cada `jal` 1, y cada branch tomado o `jalr` 2.

- **¿Qué ves en el snapshot cuando hay un stall de load-use?**

`o_stall = 1`. IF/ID muestra la misma instrucción en dos snapshots seguidos, y en el ciclo siguiente ID/EX aparece con `valid = 0` (la burbuja). Un ciclo después, la instrucción dependiente aparece en EX con `fwd = 01`.
