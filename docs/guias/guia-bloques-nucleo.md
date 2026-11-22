# Guía de los bloques del núcleo (H2-E1 y H2-E2, US-201 a US-210)

Cómo funcionan los bloques combinacionales y de memoria del núcleo, que se van a conectar en las etapas del pipeline.

## 1. Panorama

### 1.1 Bloques de H2-E1

| Archivo          | Etapa   | Tipo                 | Qué hace                                                                                      |
| ---------------- | ------- | -------------------- | --------------------------------------------------------------------------------------------  |
| `alu.v`          | EX      | comb.                | Opera A y B según `alu_ctrl`: suma, resta, lógicas, desplazamientos, comparaciones y `PASS_B` |
| `alu_control.v`  | EX      | comb.                | Traduce `alu_op` + `funct3` + `funct7[5]` al `alu_ctrl` de 4 bits                             |
| `reg_file.v`     | ID / WB | sec. + lectura comb. | 32 registros de 32 bits en FF, `x0` fijo en 0, bypass WB→ID y puerto de depuración            |
| `control_unit.v` | ID      | comb.                | Decodifica `opcode`/`funct3`/`funct7`: señales de control, `imm_type`, HALT, ilegal, `uses_rs*` |
| `imm_gen.v`      | ID      | comb.                | Reordena el inmediato del formato I/S/B/U/J y lo extiende con signo                           |
| `instr_mem.v`    | IF      | sec. + lectura comb. | IMEM de 256 palabras en LUTRAM; lee `mem[pc/4]` sin latencia; la carga la Debug Unit          |
| `data_mem.v`     | MEM     | sec. + lectura comb. | DMEM de 256 palabras con byte enables; mux de escritura núcleo / Debug Unit                   |
| `dmem_bitmap.v`  | MEM     | sec.                 | Un bit por palabra escrita y contador de palabras usadas                                      |
| `store_align.v`  | MEM     | comb.                | Arma los byte enables y replica el dato de `sb`/`sh`/`sw` en la palabra                       |
| `load_extend.v`  | MEM     | comb.                | Saca el byte o la media palabra de la palabra leída y la extiende (signo o ceros)             |

### 1.2 Lo que agrega H2-E2 (y H3-E1)

Los bloques de  son piezas sueltas. H2-E2 los agrupa en etapas, agrega lo que falta para que el pipeline funcione y los une en `riscv_core`:

| Archivo                                         |      | Qué agrega                                                                                                  |
| ----------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------- |
| `if_stage.v`                                    |  | Registro **PC**, sumador `pc + 4`, mux del próximo PC; instancia la IMEM                                     |
| `if_id_reg.v`                                   |  | Latch IF/ID con stall, flush y bit `valid`                                                                   |
| `id_stage.v`                                    |  | Extrae los campos de la instrucción; instancia banco, `control_unit` e `imm_gen`; sumador del destino del `jal` |
| `id_ex_reg.v`                                   |  | Latch ID/EX: burbuja que anula el control                                                                    |
| `ex_stage.v`, `branch_cmp.v`                    |  | Muxes de forwarding, mux `alu_src`, ALU, comparador de branches, sumador del destino y `redirect_ex`         |
| `ex_mem_reg.v`                                  |  | Latch EX/MEM (sin stall ni flush)                                                                            |
| `mem_stage.v`                                   |  | Une `store_align`, `data_mem`, `dmem_bitmap` y `load_extend`                                                 |
| `mem_wb_reg.v`, `wb_stage.v`                    |  | Latch MEM/WB, mux de `result_src` y detección del HALT que se retira                                         |
| `riscv_core.v`                                  |  | Integración: enable efectivo, `o_halted`, reset por `i_flush_all`, buses planos del snapshot                  |
| `forwarding_unit.v`, `hazard_unit.v`            |  | Forwarding, stall load-use y toda la lógica de flush / próximo PC                                   |

## 2. Patrones de Verilog que se repiten

### 2.1 Los `*_defs.vh`: `localparam` incluido dentro del módulo

```verilog
// alu.v:36
    `include "alu_defs.vh"
    `include "control_defs.vh"
```

Se eligió usar localparams en vez de macros (defines) para evitar conflictos ademas es lo mas correcto ya que son valores importantes para esos bloques nada mas, se usan macros para valores globales. A su vez al usar localparams el include debe estar dentro del modulo, porque sino seria un error de sintaxis.

### 2.2 `lint_off` de Verilator: cuándo y por qué

```verilog
// data_mem.v:28-30
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [             31:0] i_addr,
    /* verilator lint_on UNUSEDSIGNAL */
```

en los `.vh` se usa `UNUSEDPARAM`, porque cada módulo usa una parte de las constantes.

`UNUSEDSIGNAL` en puertos que reciben más bits de los que usan (`i_addr`, `i_pc`, `i_instr[6:0]` de `imm_gen`). Se recibe el bus entero para que cada módulo decida qué bits usa (las memorias según su tamaño, imm_gen con los índices de la especificación).

### 2.3 Valores por defecto al inicio del `always @(*)`

En un `always @(*)`, si en algún camino del if/case una salida no recibe valor, para verilog se mantiene el valor que tenía. Para recordar un valor sin reloj, vivado infiere un latch para eso, lo cual no es deseable en un diseño sincronico debido a que puede que se maneje mal el analisis de timing o se genere un glitch.

Por eso todos los bloques combinacionales arrancan asignando un valor a cada salida y después lo pisan según el caso (`store_align`, `load_extend`, `hazard_unit`, el mux de `wb_stage`). Además, el `default` de cada `case` repite ese valor, así un código no previsto (por ejemplo `result_src = 11`) da algo definido.

## 3. ALU y control de ALU (US-201)

El bloque alu control tiene por fin determina a partir de alu_op, el funct3 y el bit 5 de funct7 que operacion debe hacer la ALU, mientras que la control unit en la etapa de ID se encarga de generar las señales de control unicamente.

### 3.1 Dos niveles de decodificación: `alu_op` → `alu_ctrl`

la señal `alu_op` que sale de la control unit y entra en la alu control le dice como interpretar los bits del funct3 y el bit 5 de funct7 al obtener la operacion que debe hacer la ALU

### 3.2 `PASS_B`

PASS_B es la operación de la ALU que deja pasar la entrada `i_b` tal cual, sin operar con A, se usa para la instruccion `lui`

### 3.3 `SHAMT`

Como los registros son de 32 bits la cantidad maxima de desplazamientos que se puede llegar a dar es 31, para representar este numero solo basta con 5 bits. Por esto solamente se toman los 5 bits menos significativos de B `i_b`

```verilog
 wire [SHAMT_BITS-1:0] w_shamt = i_b[SHAMT_BITS-1:0];
```

## 4. Banco de registros (US-202)

En el caso de banco `i_enable` lo tienen solo dos: `reg_file` y `data_mem`, sirve para congelar el núcleo sin tener que tocar el reloj.

```verilog
// La escritura efectiva: la misma condicion habilita el flanco y el bypass.
wire               w_escribe = i_we && i_enable && (i_rd_addr != X0);
```

### 4.1 Que es el bypass por que hace falta?

El bypass se da cuando una instruccion lee un registro otra instruccion esta escribiendo en etapa de WB (osea entro a WB justo cuando este entro a ID), sin el bypass se deberia esperar 1 ciclo para que ese registro se guarde en la memoria de registros y recien ahi podria ser usado, esto es evitado por el bypass el cual le pasa directamente el valor que tiene el registro en la etapa de WB para que pueda continuar la ejecucion sin esperar ese ciclo.

En el codigo:

```verilog
assign o_rs1_data = (i_rs1_addr == X0) ? {NBIT{1'b0}} : (w_escribe && i_rd_addr == i_rs1_addr) ? i_wr_data : r_regs[i_rs1_addr];
assign o_rs2_data = (i_rs2_addr == X0) ? {NBIT{1'b0}} : (w_escribe && i_rd_addr == i_rs2_addr) ? i_wr_data : r_regs[i_rs2_addr];
```

esto se evalúa de arriba hacia abajo y gana la primera condición que se cumpla:

1. Si se lee X0 se devuelve 0, ya que este registro es inmutable y vale siempre 0
2. Si la instruccion que esta en WB está escribiendo justo el registro que se lee (rd == rs1) entonces hace el bypass y devuelve directamente el valor del registro que viene de WB.
3. Si no se da ninguna, devuelve el valor del registro está guardado en el banco.

### 4.2 Flip-flops, no LUTRAM

Al implementar el banco de registros mediante flip-flops en vez de LUTRAM, se puede hacer el borrado de los datos del banco en un solo ciclo, si fuese LUTRAM al ser una memoria (ADDRESS+DATA por ciclo), requeriria de 32 ciclos para ser borrados

## 5. Control principal e inmediatos (US-203)

### 5.1 Dos `always`: legalidad y señales

En la unidad de control se tienen dos bloques always, el primero verifica que la instruccion sea valida y la segunda activa y desactiva señales de control en funcion de la instruccion que le llego.

### 5.2 Imm generator

El imm generator se encarga de reordenar el inmediato que se encuentra dispero en la instruccion, dependiendo el tipo de instruccion y extiende el signo siempre

## 6. Memorias (US-204)

### Memoria de instrucciones

### 6.1 Dirección de byte (PC) frente a dirección de palabra (arreglo)

La memoria de instrucciones por dentro esta implementada como un arreglo de 32x256, pero el PC aumenta de 4 en 4 (su unidad minima es el byte) y las instrucciones solo se leen de a palabra (32 bits) por lo tanto es necesario reacondicionar la señal del PC para poder obtener la palabra dentro del arreglo.

Para esto se hace lo siguiente:

- Se descartan [1:0] (Byte offset), porque dividir por 4 equivale a sacar esos bits. Ademas estos deberian valer 00 siempre, porque el PC es múltiplo de 4.
- Se toman ADDR bits, por ejemplo para una memoria de 256, ADDR es 8 (se le suma el Byte offset para tomar esa parte)[9:2].
- Se ignoran los demas bits, siguiendo el ejemplo anterior seria [31:10].

```verilog
// Indice de palabra: bits [ADDR_BITS+1:2] del PC
wire [ADDR_BITS-1:0] w_word_addr = i_pc[ADDR_BITS+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
```

### Memoria de datos y Bitmap

En dmem_bitmap se implementan el bitmap, el cual tiene un bit por palabra, que indica si esa palabra fue escrita al menos una vez y un contador que cuenta cuántas palabras distintas se escribieron. La señal que indica que se escribio un dato y en que direccion la recibe de la memoria de datos

### 6.2 Escritura (memoria de datos + store align)

Al igual que en la memoria de instrucciones la memoria de datos se implementa como un arreglo de 32x256. El acondicionamiento de la direccion en la cual se va a escribir el dato se maneja entre la memoria de datos y el store align.

La memoria de datos solo necesita el indice dentro del arreglo de la palabra en el cual se va a leer o escribir el dato. Mientras que para escritura el store align proporciona el conjunto de bytes dentro de dicha palabra en el cual se va a escribir el dato. Por esta razon se repite el mismo patron que en el apartado anterior para obtener el indice dentro del arreglo.

```verilog
// Palabra que direcciona el nucleo
wire [ADDR_BITS-1:0] w_core_addr = i_addr[ADDR_BITS+BYTE_OFFSET_BITS-1 : BYTE_OFFSET_BITS];
```

### 6.3 Lectura (memoria de datos + load extend)

En el caso de lectura la memoria de datos hace lo mismo lo que modifica el resultado final es el load extend. La memoria de datos devuelve la palabra completa que se lee y load extend se encarga de mover el byte o la media palabra a la parte baja y extender a 32 bits, con el signo (lb, lh) o con ceros (lbu, lhu).

### 6.4 Exclusion de escritura entre debug unit y core

Tanto el núcleo como la Debug Unit pueden escribir en la memoria. El mux del puerto le da prioridad a la debug unit, si `i_dbg_we=1`, se escribe la limpieza y el store del núcleo se descarta. Para que ese store tampoco marque el bitmap, se define una señal de store efectivo que usan tanto la escritura como el bitmap: el núcleo escribe solo si la instrucción es un store, no es una burbuja lo cual se valida mediante el `i_valid`, el núcleo no está congelado (`i_enable`) y la Debug Unit no está escribiendo (`!i_dbg_we`).

```verilog
// Store efectivo del nucleo: la misma condicion escribe la memoria y marca el bitmap.
wire                 w_core_we = i_we && i_valid && i_enable && !i_dbg_we;
```

## 7. Stores y loads de byte y media palabra (US-205)

### Store align

La función de este bloque es preparar un store para la memoria de datos: le indica qué bytes de la palabra se escriben y le entrega el dato ya ubicado en esos bytes. Recibe tres señales:

- `i_funct3`: el tipo de store, que define qué parte de i_data se guarda: un byte (sb), media palabra (sh) o la palabra entera (sw).
- `i_addr_low`: los 2 bits bajos de la dirección, que indican en qué posición de la palabra se guarda. Un byte tiene 4 posiciones posibles y una media palabra, 2 (mitad baja o mitad alta).
- `i_data`: el valor a guardar (rs2).

Y genera dos salidas: `o_be` (los byte enables, un bit por byte de la palabra) y `o_data` (el dato que recibe la memoria).

```verilog
// store_align.v:41-62
always @(*) begin
    o_be   = BE_NINGUNO;
    o_data = i_data;
    case (i_funct3)
        F3_SB: begin
            o_be   = BE_BYTE_0 << i_addr_low;
            o_data = {4{i_data[7:0]}};
        end
        F3_SH: begin
            o_be   = i_addr_low[1] ? BE_MITAD_ALTA : BE_MITAD_BAJA;
            o_data = {2{i_data[15:0]}};
        end
        F3_SW: begin
            o_be   = BE_TODOS;
            o_data = i_data;
        end
        default: begin
            o_be   = BE_NINGUNO;
            o_data = i_data;
        end
    endcase
end
```

El dato se envía con la parte a guardar repetida en todas las posiciones posibles. Así, sea cual sea el byte que habilita `o_be`, el dato ya está en ese lugar, y la memoria lo copia sin moverlo. Los bytes que no habilita `o_be` no se escriben, así que no importa qué tengan.

Por ejemplo para la instruccion `sb x5, 2(x0)` con `x5=0x00000006` (00000110), la direccion de la palabra dentro de la memoria donde se va a escribir es en 0x00, y el offset de bytes dentro de dicha palabra va a ser 2 (`i_addr_low=2` (10)) a la salida del store align `o_data=0x06060606` y `o_be=4'b0100`

### Load extend

Como bien se menciono anteriormente, de la memoria de datos solamente salen palabras, en caso de necesitar un byte o media palabra dentro de esa palabra el load extend se encarga de acondicionarla.

Primero en caso de pedir un byte almacena el byte solicitado dentro de la palabra y de igual manera en caso de una media palabra, esto lo hace a partir del `i_addr_low` que cumple la misma funcion que Store align indicar el byte o media palabra dentro de la palabra

```verilog
always @(*) begin
    r_byte = i_word[7:0];
    case (i_addr_low)
        2'd0: r_byte = i_word[7:0];
        2'd1: r_byte = i_word[15:8];
        2'd2: r_byte = i_word[23:16];
        2'd3: r_byte = i_word[31:24];
        default: r_byte = i_word[7:0];
    endcase
    r_mitad = i_addr_low[1] ? i_word[31:16] : i_word[15:0];
end
```

Habiendo obtenido el dato procede a extenderlo con o sin signo dependiendo de la instruccion, esto se infiere a partir del valor de `i_funct3`

```verilog
// Extension segun el tipo de load
always @(*) begin
    o_data = 32'h0000_0000;
    case (i_funct3)
        F3_LB:   o_data = {{24{r_byte[7]}}, r_byte};
        F3_LBU:  o_data = {24'h00_0000, r_byte};
        F3_LH:   o_data = {{16{r_mitad[15]}}, r_mitad};
        F3_LHU:  o_data = {16'h0000, r_mitad};
        F3_LW:   o_data = i_word;
        default: o_data = 32'h0000_0000;
    endcase
end
```

## 8. Etapa IF y latch IF/ID (US-206)

Este bloque instancia e implementa los sub-bloques de la etapa IF, el cual sera instanciado en un superbloque core

### Concepto Stall, Flush y burbuja

|           | Qué le hace al latch en el flanco              | Qué pasa con la instrucción                | Cuándo                                           |
| --------- | ---------------------------------------------- | ------------------------------------------ | ------------------------------------------------ |
| **Stall** | **No carga**: se queda con lo que tenía        | **Espera** un ciclo y no se pierde         | load-use (IF/ID con `stall_d`; PC con `stall_f`) |
| **Flush** | Carga una **burbuja** en lugar de lo que venía | **Se descarta**: era del camino equivocado | redirección (`flush_d`, `flush_e`)               |

Tanto el flush como el stall generan una burbuja. Con un flush, la instrucción que iba a entrar al latch se descarta (era del camino equivocado) y en su lugar entra una burbuja. Con un stall, el latch conserva su instrucción para que espere a que avance una más antigua (el lw), y la burbuja entra en el latch siguiente para no duplicar la instrucción que espera.

### 8.1 Entradas de `if_stage`

El stall es activado por la hazard unit cuando hay un riesgo tipo load-use, por ejemplo:

```
lw x1, 2(x0)
add x2, x1, x3
```

El valor de x1, esta disponible en la etapa WB, requeriendo que la siguiente instruccion se congele un ciclo en ID para poder tener el valor de x1.

```
  ciclo          │   1   │   2   │   3   │   4   │   5   │   6   │
  clock        ──┘‾‾‾└───┘‾‾‾└───┘‾‾‾└───┘‾‾‾└───┘‾‾‾└───┘‾‾‾└───
                 ↑       ↑       ↑       ↑       ↑       ↑
  IF           ──┤  lw   │  add  │       │       │       │       │
  ID (IF/ID)   ──┤       │  lw   │  add  │  add  │       │       │
  EX (ID/EX)   ──┤       │       │  lw   │ bubbl │  add  │       │
  MEM (EX/MEM) ──┤       │       │       │  lw   │ bubbl │  add  │
  WB (MEM/WB)  ──┤       │       │       │       │  lw   │ bubbl │

  stall        ______________________/‾‾‾‾‾‾‾\________________________
  fwd_a        ──────── 00 ──────────────────────│  01   │── 00 ───
```

Lo que muestra esta imagen es que cuando la instruccion de add este en EX, le llega el valor de x1 desde WB, gestionado por la forward unit

### 8.2 Mux del próximo PC con prioridad

El mux se realiza mediante prioridades, donde la redireccion desde EX (salto condicional o jalr) > redireccion desde ID (salto incondicional, sin contar jalr) > pc+4. Esto tiene un motivo fundamental: La que se resulve mas tarde es la que gana porque su decision anula a las que vinieron despues

> Este es el código de US-206. Desde US-303 la prioridad la decide la hazard unit y `if_stage` solo obedece a `i_pc_sel` (ver la sección 15). Las secciones 8.2 y 8.3 quedan porque explican por qué el orden es ese.

```verilog
// if_stage.v en US-206
always @(*) begin
    r_pc_next = w_pc_plus4;
    if (i_redirect_ex) r_pc_next = i_redirect_ex_pc;
    else if (i_redirect_jal) r_pc_next = i_jal_pc;
end
```

### 8.3 Cuándo se escribe el PC: la redirección de EX le gana a la detención

```verilog
// if_stage.v en US-206 (desde US-303: i_enable && !i_stall_f, y la hazard unit
// no pone stall_f cuando hay redireccion de EX, salvo con ABORT)
wire w_pc_we = i_enable && (i_redirect_ex || (!i_stall && !i_halt_fetch));
```

De esta parte lo mas interesante es que la escritura de next pc se habilita a pesar de que haya un stall o un halt si se trata de salto condicional o jalr (redireccion desde EX), esto es mas visible con un ejemplo:

```
0x00  addi x1, x0, 2        # contador = 2
  loop:
  0x04  addi x1, x1, -1
  0x08  bne  x1, x0, loop     # mientras x1 no sea 0, vuelve
  0x0C  halt                  # el ensamblador lo agrega solo al final
```

El bne se resuelve en EX pero halt se detecta en ID. En el primer paso por el lazo, cuando el `bne` (0x08) está en EX, el HALT (0x0C) ya está en ID y activó `halt_fetch`. Si `halt_fetch` bloqueara también la redirección, el PC nunca volvería a `loop` y el programa terminaría con `x1 = 1` en vez de `x1 = 0`. El HALT era especulativo (venía detrás de un branch tomado), así que la redirección de EX tiene que poder escribir el PC igual, y el flush de ID/EX descarta el HALT.

### 8.4 Latch IF/ID y el bit `valid`

si i_valid = 0, IF tiene la busqueda detenida (HALT o ilegal en ID, o ABORT), entonces lo que sale de la IMEM no es una instruccion valida, no debe ejecutarse
si i_flush = 1, indica que la instruccion que busco IF es del camino equivocado (hay un jal en ID o se resolvio un salto en EX), se descarta antes de que llegue a tener efecto

En ambos casos se mete una burbuja, en este caso se usa la instruccion NOP pero podria ser cualquiera ya que esta de igual manera no se va a ejecutar a posterior, lo que importa es el valid = 0. Se usa NOP para que en el snapshot no aparezca una instruccion "real" en un latch vacio.

```verilog
// if_id_reg.v:38 y 52-60
wire w_burbuja = i_flush || !i_valid;

always @(posedge clock) begin
    if (i_reset) begin
        o_instr <= INSTR_NOP;
        o_valid <= 1'b0;
    end else if (i_enable && (i_flush || !i_stall)) begin
        o_instr <= w_burbuja ? INSTR_NOP : i_instr;
        o_valid <= !w_burbuja;
    end
end
```

Ademas hay que decidir si se esta ante un congelamiento (osea los valores tienen que mantenerse) esto se hace evaluando i_enable e i_stall: si i_enable = 0, o si i_stall esta activado y no hay flush, no se cambia ni el valid ni la instruccion. Con flush se carga igual aunque haya stall, porque mantener dejaria en ID una instruccion del camino equivocado. Si se carga y es una burbuja (flush o i_valid = 0) se carga un NOP (de relleno, es no valido) y sino la instruccion y se dice valida

## 9. Latch ID/EX (US-207)

### 9.1 `DEBUG_TRACE`

En el funcionamiento normal luego de ID, las siguientes etapas nunca trabajan con la instruccion como tal sino con sus distintas partes, pero para poder debugear y saber que instruccion habia en cada etapa es necesario propagar la instruccion. DEBUG_TRACE permite decidir si se desea guardar la instruccion.

```verilog
// id_ex_reg.v:83-84
localparam [31:0] INSTR_BURBUJA = (DEBUG_TRACE != 0) ? INSTR_NOP : 32'h0000_0000;
wire       [31:0] w_instr = (DEBUG_TRACE != 0) ? i_instr : 32'h0000_0000;
```

### 9.2 Condiciones para poner una burbuja en EX

1.  el valid desactivado implica que la instruccion que venia de la etapa anterior es una burbuja
2.  el flush activado indica que no se tiene que ejecutar la instruccion actual, porque el programa toma otro flujo de ejecucion (decidido en EX, osea branch tomado o jalr)
3.  bubble indica que la burbuja nace acá, porque IF/ID está holdeando una instrucción válida (load-use). (siguiendo el ejemplo de antes con el lw y el add, seria el add). Hay que dejar que pase un ciclo en EX y justamente lo que activa este mecanismo es esto.

```verilog
wire        w_burbuja = i_flush || i_bubble || !i_valid;
```

### 9.3 Sin stall: diferencia con IF/ID

A diferencia del registro anterior, no hay condicion que afecte a la decision de propagar o no la instruccion (salvo el enable obviamente), lo que si se afecta es que instruccion propagar y el valid con el mismo criterio que en ese latch. Si es una burbuja, se carga un nop o 0 dependiendo del debug trace y se pone el valid a 0, en caso contrario se propaga la instruccion y el valid en 1

```verilog
// id_ex_reg.v:147-155
always @(posedge clock) begin
    if (i_reset) begin
        o_instr <= INSTR_BURBUJA;
        o_valid <= 1'b0;
    end else if (i_enable) begin
        o_instr <= w_burbuja ? INSTR_BURBUJA : w_instr;
        o_valid <= !w_burbuja;
    end
end
```

### 9.4 La burbuja anula el control, no los datos

Con una burbuja, ID/EX pone en 0 todas las señales de control y carga los datos (`pc`, operandos, `imm`, `rs1`, `rs2`, `rd`, ...) igual que siempre.

```verilog
// id_ex_reg.v:104-113 (datos) y 132-142 (control), resumido
o_pc        <= i_pc;                             // datos: se cargan siempre
o_rd        <= i_rd;
...
o_reg_write <= w_burbuja ? 1'b0 : i_reg_write;   // control: en 0 si es burbuja
o_branch    <= w_burbuja ? 1'b0 : i_branch;
o_halt      <= w_burbuja ? 1'b0 : i_halt;
...
```

No hace falta anular los datos, porque sin control ningún bloque los usa, y anularlos sería un mux más por cada bit. Además, el snapshot muestra qué instrucción se descartó: después de un flush, ID/EX queda con valid = 0 pero con el pc y el rd de la instrucción que se mató.

Ademas al anular las señales de control se protege los datos de la burbuja. Una burbuja por flush conserva el rd de la instrucción descartada (por ejemplo, x1). Si la forwarding unit comparara solo registros, vería ese rd = x1 en EX/MEM o MEM/WB y le pasaría basura a la instrucción en EX. No pasa porque el forwarding también pide reg_write = 1, y en la burbuja vale 0.

## 10. Etapa EX y latch EX/MEM (US-208)

`ex_stage` es combinacional e instancia `alu_control`, `alu` y `branch_cmp`. Calcula el resultado de la instrucción y decide si EX redirige el PC. `pc_plus4`, `rd` y las señales de control de MEM y WB no pasan por la etapa: van de ID/EX a EX/MEM directo.

### 10.1 `store_data` sale antes del mux `alu_src`

```verilog
// ex_stage.v:79-80
assign w_alu_b      = i_alu_src ? i_imm : r_op_b;
assign o_store_data = r_op_b;
```

Un store usa los dos operandos para cosas distintas: la ALU calcula la dirección con rs1 + imm, y el dato a guardar es rs2. Por eso el mux 2 a 1 tiene la posibilidad de seleccionar el operando B o el inmedianto, y a su vez el operando B pasa directamente al registro EX/MEM

### 10.2 Forwarding: el selector `11`

Los dos operandos pasan por un mux de forwarding de 3 entradas, pero el selector es de 2 bits, así que hay un cuarto valor posible:

```verilog
// ex_stage.v:59-67 (operando A; el B es igual)
always @(*) begin
    r_op_a = i_rs1_data;
    case (i_fwd_a)
        FWD_MEM_WB: r_op_a = i_fwd_mem_wb;   // 01
        FWD_EX_MEM: r_op_a = i_fwd_ex_mem;   // 10
        default:    r_op_a = i_rs1_data;     // 00 y 11
    endcase
end
```

`11` no deberia darse nunca pero en caso de darse se comporta como `00`, es decir, usa el valor leído del banco en ID. Así nunca hay una salida indefinida.

### 10.3 `branch_cmp` en paralelo con la ALU

branch_cmp compara los operandos forwardeados en paralelo a la ALU. La decisión de saltar se arma aparte en redirect:

```verilog
// ex_stage.v:107 y 113
wire w_branch_taken = i_branch && ((i_funct3 == F3_BEQ) ? w_eq : !w_eq);
assign o_redirect   = i_valid && (w_branch_taken || i_jalr);
```

- `beq` salta con `eq` y `bne` con `!eq`. `control_unit` marca como ilegal cualquier otro `funct3` de branch mediante la señal `i_branch`, así que no hace falta mirar más.
- `i_valid`: una burbuja nunca redirige. En la práctica ID/EX ya puso `branch = jalr = 0` en la burbuja, y esto es una segunda protección.

### 10.4 Destinos: sumador propio para branches, ALU para `jalr`

```verilog
// ex_stage.v:110-114
wire [31:0] w_branch_target = i_pc + i_imm;
wire [31:0] w_jalr_target   = o_alu_result & JALR_MASK;   // JALR_MASK = ~1
assign o_redirect_pc = i_jalr ? w_jalr_target : w_branch_target;
```

en un branch el destino es `pc + imm_B`. La ALU no puede calcularlo porque el PC no entra en ninguna de sus entradas: A es siempre rs1 y B es rs2 o el inmediato. En vez de agregar un mux en A para que pueda tener el PC, hay un sumador propio, que calcula el destino en paralelo con el comparador.

### 10.5 Por qué `jalr` limpia solo el bit 0: la extensión C

La especificación define el destino de `jalr` como `(rs1 + imm) & ~1`. Solo el bit 0, aunque nuestras instrucciones vayan de 4 en 4.

La razón es la **extensión C** (_Compressed_). Es una extensión estándar de RISCV que agrega versiones de 16 bits de las instrucciones más usadas, para que el código ocupe menos. Con C, un programa mezcla instrucciones de 16 y 32 bits, y una instrucción puede empezar en una dirección múltiplo de 2:

```
0x00  add  (32 bits)
0x04  c.mv (16 bits)
0x06  lw   (32 bits)   ← múltiplo de 2, no de 4
```

El procesador sabe cuál es cuál por los 2 bits más bajos: `11` es una instrucción de 32 bits (todas las nuestras, incluido HALT `0001011`) y cualquier otro valor es una de 16.

RV32I está pensada para no cambiar cuando se agrega C, y por eso tiene detalles que sin C parecen raros:

- `jalr` hace `& ~1`, lo mínimo para que el destino sea par;
- los inmediatos B y J (`formatos.md`) tienen el bit 0 implícito en 0, pero codifican el bit 1: los offsets están en unidades de 2 bytes.

En nuestro caso como usamos solamente instrucciones del 32 bits, la IMEM ignora `pc[1:0]` (explicado en la seccion 6.1), así que con PC = `0x102` lee la palabra de `0x100`, y las instrucciones que se ejecutan son las mismas.

Pero fue agregado para respetar la especificacion, ademas para que lo que muestra el hardware en los snapshots (el PC y registros como x1) coincida con el golden model, que sigue la spec.

## 11. Etapas MEM y WB, y latch MEM/WB (US-209)

### 11.1 `mem_stage`: solo cableado

`mem_stage` no tiene lógica propia: instancia `store_align`, `data_mem`, `dmem_bitmap` y `load_extend` y los conecta como en el diagrama. La dirección es `alu_result` (rs1 + imm): los bits `[1:0]` van a `store_align` y `load_extend`, y `data_mem` usa `[ADDR_BITS+1:2]` (sección 6.2).

`mem_read` no entra a la etapa. La lectura de la DMEM es combinacional y siempre está disponible: si la instrucción no es un load, el dato leído se descarta en WB porque `result_src` no lo elige. `mem_read` sigue en EX/MEM solo para la hazard unit (en ID/EX) y para el snapshot.

La marca del bitmap sale de `data_mem` (`o_core_we`, `o_core_addr`), no de la etapa, para que la condición que escribe la memoria y la que marca el bitmap sea una sola (sección 6.4).

### 11.2 EX/MEM y MEM/WB no crean burbujas

A diferencia de IF/ID e ID/EX, estos dos latches no tienen stall ni flush: cargan lo que llega siempre que `i_enable = 1`.

```verilog
// mem_wb_reg.v (ex_mem_reg.v es igual)
end else if (i_enable) begin
    o_instr <= w_instr;
    o_valid <= i_valid;
end
```

- **Sin flush:** las redirecciones se resuelven a más tardar en EX, así que todo lo que pasó de EX es del camino correcto.
- **Sin stall:** el único stall (load-use) frena IF e ID; el load sigue avanzando para que su dato llegue.
- **Las burbujas pasan tal cual:** llegan de ID/EX con `valid = 0` y el control ya en 0 (sección 9.4), y se copian.

### 11.3 `wb_stage`: mux de `result_src` y qué se escribe

```verilog
// wb_stage.v
always @(*) begin
    o_wb_data = i_alu_result;
    case (i_result_src)
        RES_MEM: o_wb_data = i_mem_data;   // loads
        RES_PC4: o_wb_data = i_pc_plus4;   // jal / jalr
        default: o_wb_data = i_alu_result; // RES_ALU y 11
    endcase
end

assign o_wb_we        = i_valid && i_reg_write;
assign o_halt_retired = i_valid && i_halt;
```

- Por eso MEM/WB guarda tres valores de 32 bits (`alu_result`, `mem_data`, `pc_plus4`): el mux está en WB, después del latch.
- `o_wb_data` es `ResultW` en el diagrama: va al banco (`WD3`) y también es la entrada `FWD_MEM_WB` de los muxes de forwarding en EX.
- `o_wb_we` vuelve a mirar `valid`. Una burbuja ya trae `reg_write = 0`, así que es una segunda protección, como `i_valid` en `redirect_ex` (sección 10.3).
- `o_halt_retired` indica que el HALT (o la ilegal) terminó de recorrer el pipeline: todas las instrucciones anteriores ya escribieron. Dura un ciclo; `riscv_core` lo guarda (sección 12.2).

## 12. Integración del núcleo (US-210)

`riscv_core` instancia las cinco etapas, los cuatro latches, la hazard unit y la forwarding unit. Lo que no pertenece a ninguna etapa vive acá:

```verilog
// riscv_core.v:189-191
wire w_rst = i_reset || i_flush_all;   // reset de PC, latches y banco
wire w_en  = i_enable && !r_halted;    // con el programa terminado, no avanza
```

### 12.1 Dónde quedó cada memoria

El banco de registros está dentro de `id_stage`, aunque lo escribe WB: las señales de escritura (`o_wb_we`, `o_wb_rd`, `o_wb_data`) salen de `wb_stage` y vuelven a `id_stage` como `i_wb_*`. La IMEM está en `if_stage` y la DMEM y el bitmap en `mem_stage`. Los puertos de la Debug Unit (carga de IMEM, lectura de registros y memoria, limpieza) atraviesan esas etapas hasta el bloque que corresponde.

### 12.2 `o_halted` y el enable efectivo

```verilog
// riscv_core.v:203-211
always @(posedge clock) begin
    if (w_rst) begin
        r_halted  <= 1'b0;
        r_illegal <= 1'b0;
    end else if (w_en && w_wb_halt_retired) begin
        r_halted  <= 1'b1;
        r_illegal <= w_wb_illegal_retired;
    end
end
```

Cuando el HALT llega a WB, `r_halted` se pone en 1 y `w_en` baja a 0. `w_en` es el `i_enable` de todo el núcleo (PC, latches, banco, DMEM, hazard unit), así que el pipeline queda congelado con el estado final aunque la Debug Unit siga mandando `i_enable = 1`. El HALT queda en MEM/WB y se ve en el snapshot. Solo `i_reset` o `i_flush_all` lo sacan de ese estado.

El HALT se detecta en ID (para dejar de buscar) pero el núcleo se detiene recién en WB: así las instrucciones anteriores al HALT terminan de escribir antes de que la Debug Unit lea registros y memoria.

### 12.3 `i_reset`, `i_flush_all` e `i_clear_used`

| Señal          | PC y latches | Banco | Bitmap | Necesita `i_enable` |
| -------------- | ------------ | ----- | ------ | ------------------- |
| `i_reset`      | sí           | sí    | sí     | no                  |
| `i_flush_all`  | sí           | sí    | no     | no                  |
| `i_clear_used` | no           | no    | sí     | no                  |

`i_flush_all` es lo que usa la Debug Unit para volver a correr un programa (ADR-009): deja el núcleo como recién reseteado sin borrar el bitmap, que se limpia aparte. Ninguna de las tres depende de `i_enable`, porque la Debug Unit las usa con el núcleo congelado.

### 12.4 Los latches como buses planos

Para el snapshot (ADR-017), cada latch sale de `riscv_core` como un bus plano (`o_if_id` de 104 bits, `o_id_ex` de 248, `o_ex_mem` de 152 y `o_mem_wb` de 144), con el layout de bytes de [`riscv_core.md`](../interfaces/riscv_core.md) sección 4: byte `k` = `bus[8k+7:8k]`, y los bits sobrantes de cada byte en 0. Así la Debug Unit manda el latch byte por byte sin conocer sus campos, y el software lo decodifica con la misma tabla.

## 13. Forwarding unit (US-301)

En la forwarding unit ingresan las direcciones de los registros que se usan en la etapa de EX y se comparan contra rd en MEM y rd en WB osea lo que se hace es verifica que en la etapa de EX se va a usar registros (rs1 y rs2) que van a ser escritos (reg_write) en MEM o WB y que la operacion no es una burbuja mediante el valid. Luego notar tambien que el registro en MEM tiene mayor prioridad en la toma de la decision porque es el valor mas reciente, podria darse el caso que las instrucciones en MEM y en WB escriban el mismo registro, y el valor correcto es el de la mas reciente. Ademas se verifica que el registro no sea x0, que siempre debe valer 0: hay instrucciones con rd = x0 y reg_write = 1 (jal x0, addi x0) y, si se reenviaran, la que lee x0 recibiria un valor distinto de 0

```verilog
// forwarding_unit.v:41-49
// Aca solo se verifica si hay escritura del registro en esas etapas
wire w_escribe_mem = i_ex_mem_valid && i_ex_mem_reg_write && (i_ex_mem_rd != X0);
wire w_escribe_wb = i_mem_wb_valid && i_mem_wb_reg_write && (i_mem_wb_rd != X0);

// Operando A
// Aca se verifica que el registro que se va a escribir es el que se necesita en EX
always @(*) begin
    o_fwd_a = FWD_ID_EX;
    if (w_escribe_mem && (i_ex_mem_rd == i_id_ex_rs1)) o_fwd_a = FWD_EX_MEM;
    else if (w_escribe_wb && (i_mem_wb_rd == i_id_ex_rs1)) o_fwd_a = FWD_MEM_WB;
end
// lo mismo para el operando B
```

## 14. Hazard unit (US-302)

La hazard unit resuelve un problema que la forwarding unit no puede resolver, es el tema de load-use por ejemplo:

```
lw  x1, 0(x2)      ← el dato sale de la DMEM al final de MEM
add x3, x1, x4     ← lo necesita al principio de EX
```

El valor de x1 esta disponible recien a la salida de la fase de recuperar el dato osea a la salida del bloque Load-extend en la etapa de MEM, cuando el add ya esta en EX y lo necesita en ese mismo ciclo. Por eso no se puede reenviar: en EX/MEM todavia esta la direccion, no el dato. Para detectar este tipo de riesgo se hace lo siguiente:

1. ver si la instrucción que está en EX es válida, y lee la memoria (es un load), y su registro destino no es x0.
2. La instruccion que esta en ID necesita el registro que se carga en la instruccion anterior (que estaria en EX), y la instruccion de verdad lee ese operando (uses_rs1/uses_rs2) (en un addi, lui o jal los bits de rs pueden ser parte del inmediato)
3. Si se cumplen las dos, se hace un stall: el PC e IF/ID se mantienen (la instrucción espera en ID) y en ID/EX entra una burbuja (no se ejecuta nada en EX en el ciclo siguiente). Al ciclo siguiente el load ya está en WB y el dato llega a EX por forwarding desde MEM/WB

```verilog
// hazard_unit.v:34-39
//1.
// Load valido en EX que escribe un registro distinto de x0
wire w_load_en_ex = i_id_ex_valid && i_id_ex_mem_read && (i_id_ex_rd != X0);
//2.
// La instruccion de ID necesita el registro que carga el load
wire w_usa_rd = (i_uses_rs1 && (i_if_id_rs1 == i_id_ex_rd)) || (i_uses_rs2 && (i_if_id_rs2 == i_id_ex_rd));
//3.
assign o_stall = w_load_en_ex && w_usa_rd;
```

---

En este punto se hicieron cambios retroactivos a otros bloques. Con el fin de completar la funcionalidad de la hazard unit se cambiaron las siguientes cosas:
control_defs: Se agregaron las codificaciones para el PC_SEL en el mux de PC: PC_SEL_PLUS4, PC_SEL_JAL, PC_SEL_EX
if_stage: antes manejaba el las prioridades dentro del mux del PC, ahora obedece lo que le dice la hazard unit
hazard_unit: hasta la us-302 lo unico que manejaba era el hazard load-use, a partir de ahora pasa a manejar todo esto, que antes estaba en otros módulos:

| Qué                                                | Dónde estaba antes                                        | Ahora en la hazard unit                                                      |
| -------------------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Elegir el próximo PC (EX > `jal` > +4)             | `if_stage` (su `always` de prioridad)                     | `o_pc_sel`                                                                   |
| Flush de IF/ID (por `jal` o por redirección de EX) | `riscv_core` (`w_flush_if_id`)                            | `o_flush_d`                                                                  |
| Flush de ID/EX (redirección de EX)                 | `riscv_core` (`w_flush_id_ex`)                            | `o_flush_e`                                                                  |
| Burbuja de ID/EX por ABORT                         | `riscv_core` (`w_bubble_id_ex = stall \|\| i_stop_fetch`) | `o_bubble_e`                                                                 |
| Frenar la búsqueda por HALT o ABORT                | `riscv_core` (`w_halt_fetch`) + `if_stage`                | `o_stall_f`                                                                  |
| Registro `halt_fetch` (recordar el HALT)           | `riscv_core` (`r_halt_fetch`)                             | adentro de la unidad, por eso ahora tiene `clock`, `i_reset` e `i_enable` |
| Prioridades entre eventos simultáneos              | implícitas, repartidas en los tres lugares                | explícitas, en una sola cadena `if` / `else if`                              |

---

## 15. Hazard unit (US-303)

### 15.1 ABORT

El ABORT es una señal que le envia la DU al core, existe para los programas que nunca llegan a un HALT. Por ejemplo:

```

loop: addi x1, x1, 1
j loop
```

En modo continuo este programa corre para siempre: ningún HALT llega a WB. El relleno con HALT de la IMEM y el HALT automático del ensamblador no ayudan, porque el lazo nunca sale. ABORT es la salida de emergencia para cortarlo desde afuera.

Tanto el HALT como ABORT funciona igual, ambos activan stallF, lo que hace frenar al PC y rellenar con burbujas las siguientes etapas

### 15.2 Funcionalidades de la Hazard unit

Desde la us-303, la hazard unit decide en cada ciclo tres cosas:

- De dónde sale el próximo PC;
- Que hace cada latch del frente del pipeline (PC, IF/ID e ID/EX): carga, mantiene o mete una burbuja;
- Si la búsqueda de instrucciones sigue o se detiene.

Para eso tiene dos `always`:

- uno **combinacional**, que es la tabla de prioridades y decide las salidas del ciclo actual;
- uno **secuencial**, que es el registro `r_halt_fetch` y recuerda que se vio un HALT.

Las salidas y a dónde van:

| Salida       | Va a                     | Efecto                                                                 |
| ------------ | ------------------------ | ---------------------------------------------------------------------- |
| `o_pc_sel`   | mux del PC (`if_stage`)  | `00` = PC + 4, `01` = destino del `jal`, `10` = destino de EX          |
| `o_stall_f`  | `if_stage`               | el PC no se escribe y `o_valid = 0` (IF manda burbujas)                |
| `o_stall_d`  | `if_id_reg`              | IF/ID mantiene su instrucción                                          |
| `o_flush_d`  | `if_id_reg`              | IF/ID carga una burbuja en lugar de la instrucción de IF               |
| `o_flush_e`  | `id_ex_reg` (`i_flush`)  | ID/EX carga una burbuja en lugar de la instrucción de ID (redirección) |
| `o_bubble_e` | `id_ex_reg` (`i_bubble`) | ID/EX carga una burbuja (load-use o ABORT)                             |

### 15.3 `always` combinacional: la tabla de prioridades

```verilog
// Tabla de prioridades
always @(*) begin
    o_pc_sel   = PC_SEL_PLUS4;
    o_stall_f  = 1'b0;
    o_stall_d  = 1'b0;
    o_flush_d  = 1'b0;
    o_flush_e  = 1'b0;
    o_bubble_e = 1'b0;
    if (i_redirect_ex) begin
        // 1. Redireccion de EX: lo de IF e ID era especulativo
        o_pc_sel  = PC_SEL_EX;
        o_flush_d = 1'b1;  // Flush IF/ID: burbuja en lugar de la instruccion de IF
        o_flush_e = 1'b1;  // Flush ID/EX: burbuja en lugar de la instruccion de ID
        o_stall_f = i_stop_fetch;  // con ABORT no se busca el destino
    end else if (i_stop_fetch) begin
        // 2. ABORT: deja de buscar y descarta la instruccion de ID
        o_stall_f  = 1'b1;  // StallF: PC quieto, IF manda burbujas a IF/ID
        o_bubble_e = 1'b1;  // Burbuja en ID/EX: se descarta la instruccion de ID
    end else if (i_redirect_jal) begin
        // 3. jal en ID
        o_pc_sel  = PC_SEL_JAL;
        o_flush_d = 1'b1;  // Flush IF/ID: burbuja en lugar de la instruccion de IF
    end else if (w_load_use) begin
        // 4. Load-use: la instruccion de ID espera un ciclo
        o_stall_f  = 1'b1;  // StallF: PC quieto
        o_stall_d  = 1'b1;  // StallD: IF/ID mantiene la instruccion que espera
        o_bubble_e = 1'b1;  // Burbuja en ID/EX para no duplicarla en EX
    end else if (w_halt_fetch) begin
        // 5. HALT/ilegal: deja de buscar
        o_stall_f = 1'b1;  // StallF: PC quieto, IF manda burbujas a IF/ID
    end
end
```

Arranca con todas las salidas en el caso "no pasa nada": PC + 4, sin stall y sin flush. Si no se cumple ninguna condición, el pipeline avanza normalmente.

En un mismo ciclo pueden pasar varias cosas a la vez. Por ejemplo, un branch tomado en EX mientras en ID hay un `jal`, un HALT o una instrucción con load-use. Cada evento pide algo distinto, así que la cadena `if` / `else if` decide la prioridad. **Gana la instrucción más vieja**, porque si ella cambia el flujo, todo lo que vino detrás es del camino equivocado y no debería tener efecto.

1. **Redirección de EX** (branch tomado o `jalr`). Es la instrucción más vieja que puede cambiar el flujo, así que lo que está en IF y en ID es especulativo: se descarta con `flush_d` y `flush_e`, y el PC toma el destino calculado en EX. Por eso un branch cuesta 2 ciclos. Si además hay un ABORT, `stall_f = i_stop_fetch` deja el PC quieto: se descarta lo especulativo, pero no se busca el destino.
2. **ABORT**. Viene de la debug unit, así que le gana a todo lo que esté en ID: `stall_f` detiene la búsqueda y `bubble_e` descarta la instrucción de ID. Lo que ya está en EX, MEM y WB termina normalmente.
3. **`jal` en ID**. Se resuelve en ID, así que solo la instrucción de IF es del camino equivocado: `flush_d` la descarta y el PC toma el destino del `jal`. Cuesta 1 ciclo. El `jal` sigue a EX, porque tiene que escribir `rd = pc + 4`.
4. **Load-use**. Igual que en US-302: la instrucción de ID espera un ciclo. Ahora el stall se reparte en `stall_f` (PC) y `stall_d` (IF/ID), y la burbuja en ID/EX sale por `bubble_e`.
5. **HALT** (o ilegal). Solo detiene la búsqueda con `stall_f`. No pone `bubble_e`, porque la instrucción de ID es el propio HALT y tiene que llegar a WB para que el core se detenga (`o_halted`).

Notar que en ABORT se detiene el PC y se descarta la instruccion en ID, mientras que un halt o illegal solamente detiene el PC y deja que se continue ejecutado las etapas posteriores sin agregar burbujas

### 15.4 `always` secuencial: `r_halt_fetch`

```verilog
// Busqueda detenida por un HALT/ilegal: el de este ciclo en ID o uno detectado antes
wire w_halt_fetch = r_halt_fetch || i_halt_detected;

// halt_fetch pegajoso
always @(posedge clock) begin
    if (i_reset) begin
        r_halt_fetch <= 1'b0;
    end else if (i_enable) begin
        if (i_redirect_ex) r_halt_fetch <= 1'b0;
        else if (i_halt_detected && !i_stop_fetch) r_halt_fetch <= 1'b1;
    end
end
```

`i_halt_detected` vale 1 **solo mientras el HALT está en ID**, o sea, un ciclo. Pero la búsqueda tiene que seguir detenida hasta que el HALT llegue a WB y el core se congele. Por eso hace falta un registro "pegajoso" que recuerde que se vio un HALT.

`w_halt_fetch` junta dos términos, uno para cada momento:

| Ciclo            | `i_halt_detected`         | `r_halt_fetch`                         | `w_halt_fetch` |
| ---------------- | ------------------------- | -------------------------------------- | -------------- |
| HALT en ID       | **1**                     | 0 (todavía no se cargó)                | 1              |
| HALT en EX       | 0 (en ID hay una burbuja) | **1** (se cargó en el flanco anterior) | 1              |
| HALT en MEM y WB | 0                         | **1**                                  | 1              |

- **Sin `i_halt_detected`:** en el ciclo en que el HALT está en ID, la instrucción que viene detrás (en IF) entraría a IF/ID como válida.
- **Sin `r_halt_fetch`:** desde el ciclo siguiente el PC volvería a buscar instrucciones.

Cuando el HALT llega a WB, `riscv_core` pone `o_halted = 1` y `w_en = 0`. Como `w_en` es el `i_enable` de la hazard unit, el registro queda congelado en 1 hasta un reset.

Condiciones del registro:

- **Reset** (`i_reset`, que en el core es `i_reset || i_flush_all`): vuelve a 0. Actúa aunque `i_enable = 0`, igual que en los latches.
- **Redirección de EX**: no se prende, o se borra. Si un branch más viejo salta, el HALT de ID era especulativo y `flush_e` lo descarta, así que no hay que detener la búsqueda. En el `always` combinacional pasa lo mismo: la redirección (prioridad 1) le gana al HALT (prioridad 5), así que en ese ciclo tampoco hay `stall_f` por el HALT.
- **HALT en ID con ABORT**: no se prende. Ese HALT se descarta con `bubble_e`, y la búsqueda ya está detenida por `i_stop_fetch`, que la DU mantiene en 1. No hay nada que recordar.
