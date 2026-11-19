# Guía de los bloques del núcleo (H2-E1 y H2-E2, US-201 a US-210)

Cómo funcionan los bloques combinacionales y de memoria del núcleo, que la épica H2-E2 va a conectar en las etapas del pipeline. El código está en `TP3/hw/rtl/core/`; los contratos, en [`tabla_control.md`](../interfaces/tabla_control.md), [`riscv_core.md`](../interfaces/riscv_core.md) y [`formatos.md`](../interfaces/formatos.md); las decisiones, en ADR-005, ADR-008, ADR-018 y ADR-019.

> Estado: H2-E1 completa (US-201 a US-205); H2-E2 en curso (US-206). Esta guía cubre solo las partes difíciles de cada bloque, no todo el código.

## 1. Panorama

> TODO: tabla con una fila por bloque y estas columnas:
> archivo | US | etapa (IF/ID/EX/MEM/WB) | combinacional o secuencial | qué hace en una línea.
> Ubicar cada bloque en la página 2 de `datapath_pipeline.drawio`.

| Archivo          | US     | Etapa   | Tipo                 | Qué hace |
| ---------------- | ------ | ------- | -------------------- | -------- |
| `alu.v`          | US-201 | EX      | comb.                |          |
| `alu_control.v`  | US-201 | EX      | comb.                |          |
| `reg_file.v`     | US-202 | ID / WB | sec. + lectura comb. |          |
| `control_unit.v` | US-203 | ID      | comb.                |          |
| `imm_gen.v`      | US-203 | ID      | comb.                |          |
| `instr_mem.v`    | US-204 | IF      | sec. + lectura comb. |          |
| `data_mem.v`     | US-204 | MEM     | sec. + lectura comb. |          |
| `store_align.v`  | US-205 | MEM     | comb.                |          |
| `load_extend.v`  | US-205 | MEM     | comb.                |          |

> TODO: qué queda para H2-E2: los latches, el PC, el mux de `result_src`, `branch_cmp`, etc.

## 2. Patrones de Verilog que se repiten

### 2.1 Los `*_defs.vh`: `localparam` incluido dentro del módulo

```verilog
// alu.v:36
    `include "alu_defs.vh"
    `include "control_defs.vh"
```

Se eligió usar localparams en vez de macros (defines) para evitar conflictos ademas es lo mas correcto ya que son valores importantes para esos bloques nada mas, se usan macros para valores globales. A su vez al usar localparams el include debe estar dentro del modulo, porque sino seria un error de sintaxis.

### 2.3 `lint_off` de Verilator: cuándo y por qué

```verilog
// data_mem.v:28-30
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [             31:0] i_addr,
    /* verilator lint_on UNUSEDSIGNAL */
```

en los `.vh` se usa `UNUSEDPARAM`, porque cada módulo usa una parte de las constantes.

`UNUSEDSIGNAL` en puertos que reciben más bits de los que usan (`i_addr`, `i_pc`, `i_instr[6:0]` de `imm_gen`). Se recibe el bus entero para que cada módulo decida qué bits usa (las memorias según su tamaño, imm_gen con los índices de la especificación).

### 2.4 Valores por defecto al inicio del `always @(*)`

En un `always @(*)`, si en algún camino del if/case una salida no recibe valor, para verilog se mantiene el valor que tenía. Para recordar un valor sin reloj, vivado infiere un latch para eso, lo cual no es deseable en un diseño sincronico debido a que puede que se maneje mal el analisis de timing o se genere un glitch.

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

### 4.4 Flip-flops, no LUTRAM

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

```verilog
// if_stage.v:54-58
always @(*) begin
    r_pc_next = w_pc_plus4;
    if (i_redirect_ex) r_pc_next = i_redirect_ex_pc;
    else if (i_redirect_jal) r_pc_next = i_jal_pc;
end
```

### 8.3 Cuándo se escribe el PC: la redirección de EX le gana a la detención

```verilog
// if_stage.v:51
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

El bne se resuelve en EX pero halt se detecta en ID

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

En nuestro caso como usamos solamente instrucciones del 32 bits, la IMEM ignora `pc[1:0]` (explicado en la seccion 6.2), así que con PC = `0x102` lee la palabra de `0x100`, y las instrucciones que se ejecutan son las mismas.

Pero fue agregado para respetar la especificacion, ademas para que lo que muestra el hardware en los snapshots (el PC y registros como x1) coincida con el golden model, que sigue la spec.

## 11. Forwarding unit (US-301)

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

## 12. Hazard unit (US-302)

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
