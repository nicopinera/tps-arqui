// Nucleo falso para probar la Debug Unit sin el riscv_core real (US-402).
//
// Tiene exactamente los puertos y anchos de docs/interfaces/riscv_core.md (v0.1), pero en
// lugar de ejecutar instrucciones solo hace cosas predecibles:
//   - un contador `r_ciclos` que avanza en cada ciclo con i_enable = 1 (y sin halted);
//     registros, latches y senales de riesgo salen de el, asi que cualquier ciclo de mas
//     con el nucleo "congelado" se nota en el snapshot;
//   - el PC suma 4 por ciclo y la instruccion de IF/ID se lee de una IMEM real (la carga
//     la Debug Unit con LOAD);
//   - cada 4 ciclos "hace un store" en la DMEM, que marca el bitmap y el contador de usadas;
//   - los 4 bits `valid` se desplazan como en un pipeline: con i_stop_fetch entran burbujas
//     y en pocos ciclos quedan todos en 0 (fin del drenado de ABORT);
//   - termina (o_halted, y o_illegal si ILLEGAL = 1) despues de HALT_AFTER ciclos.
// Es sintetizable: no usa nada que el hardware real no pueda hacer.
module core_stub #(
    parameter NBIT           = 32,
    parameter IMEM_DEPTH     = 256,
    parameter IMEM_ADDR_BITS = 8,
    parameter DMEM_DEPTH     = 256,
    parameter DMEM_ADDR_BITS = 8,
    parameter DEBUG_TRACE    = 1,
    // Propios del stub (no estan en el contrato)
    parameter HALT_AFTER     = 0,  // ciclos con enable hasta o_halted; 0 = nunca termina
    parameter ILLEGAL        = 0   // 1 = la terminacion es por instruccion ilegal
  )(
    // 2.1 Control de ejecucion
    input  wire clock,
    input  wire i_reset,
    input  wire i_enable,
    input  wire i_flush_all,
    input  wire i_stop_fetch,
    output reg  o_halted,
    output reg  o_illegal,
    output wire [NBIT-1:0] o_pc,

    // 2.2 Carga de la IMEM
    input  wire i_imem_we,
    input  wire [IMEM_ADDR_BITS-1:0] i_imem_addr,
    input  wire [NBIT-1:0] i_imem_wdata,

    // 2.3 DMEM: limpieza y memoria usada
    input  wire i_dbg_dmem_we,
    input  wire [DMEM_ADDR_BITS-1:0] i_dbg_dmem_addr,
    input  wire i_clear_used,

    // 2.4 Lectura de depuracion (combinacional)
    input  wire [4:0] i_dbg_reg_addr,
    output wire [NBIT-1:0] o_dbg_reg_data,
    input  wire [DMEM_ADDR_BITS-1:0] i_dbg_mem_addr,
    output wire [NBIT-1:0] o_dbg_mem_data,
    output wire o_dbg_mem_used,
    output wire [DMEM_ADDR_BITS:0] o_dbg_used_count,

    // 2.5 Senales de riesgo del ciclo
    output wire o_stall,
    output wire o_flush_if_id,
    output wire o_flush_id_ex,
    output wire [1:0] o_fwd_a,
    output wire [1:0] o_fwd_b,

    // 2.6 Latches como buses planos
    output wire [103:0] o_if_id,
    output wire [247:0] o_id_ex,
    output wire [151:0] o_ex_mem,
    output wire [143:0] o_mem_wb
  );

  localparam integer HALT_AFTER_I = HALT_AFTER;
  localparam [23:0]  HALT_CICLO   = HALT_AFTER_I[23:0];  // mismo ancho que r_ciclos

  reg [NBIT-1:0] r_pc;
  reg [23:0]     r_ciclos;
  reg [3:0]      r_valid;   // [0] IF/ID, [1] ID/EX, [2] EX/MEM, [3] MEM/WB

  reg [NBIT-1:0]       r_imem [0:IMEM_DEPTH-1];
  reg [NBIT-1:0]       r_dmem [0:DMEM_DEPTH-1];
  reg [DMEM_DEPTH-1:0] r_used;
  reg [DMEM_ADDR_BITS:0] r_used_count;

  // Prioridades de la seccion 3 del contrato: reset > flush_all > enable = 0 > halted
  wire w_avanza = i_enable && !o_halted;
  // Un "store" cada 4 ciclos, en la palabra que indica el contador
  wire w_store = w_avanza && (r_ciclos[1:0] == 2'b00);
  wire [DMEM_ADDR_BITS-1:0] w_store_addr = r_ciclos[DMEM_ADDR_BITS+1:2];

  integer i;
  initial
  begin
    for (i = 0; i < IMEM_DEPTH; i = i + 1)
      r_imem[i] = {NBIT{1'b0}};
    for (i = 0; i < DMEM_DEPTH; i = i + 1)
      r_dmem[i] = {NBIT{1'b0}};
  end

  // --- PC, contador, valid y terminacion --------------------------------------------------
  always @(posedge clock)
  begin
    if (i_reset || i_flush_all)  // flush_all = reset salvo bitmap y contador (bloque de abajo)
    begin
      r_pc      <= {NBIT{1'b0}};
      r_ciclos  <= 24'd0;
      r_valid   <= 4'b0000;
      o_halted  <= 1'b0;
      o_illegal <= 1'b0;
    end
    else if (w_avanza)
    begin
      r_ciclos <= r_ciclos + 24'd1;
      if (!i_stop_fetch)
        r_pc <= r_pc + 4;
      // Con stop_fetch entran burbujas en IF/ID e ID/EX; EX y MEM siguen avanzando
      r_valid <= {r_valid[2], r_valid[1], r_valid[0] && !i_stop_fetch, !i_stop_fetch};
      if (HALT_AFTER != 0 && r_ciclos + 24'd1 == HALT_CICLO)
      begin
        o_halted  <= 1'b1;
        o_illegal <= (ILLEGAL != 0);
      end
    end
  end

  // --- IMEM: la escribe la Debug Unit sin depender de i_enable ----------------------------
  always @(posedge clock)
    if (i_imem_we)
      r_imem[i_imem_addr] <= i_imem_wdata;

  // --- DMEM, bitmap y contador de palabras usadas -----------------------------------------
  always @(posedge clock)
  begin
    if (i_dbg_dmem_we)
      r_dmem[i_dbg_dmem_addr] <= {NBIT{1'b0}};  // limpieza: no marca el bitmap
    else if (w_store && !i_reset && !i_flush_all)
      r_dmem[w_store_addr] <= {8'hD0, r_ciclos};
  end

  always @(posedge clock)
  begin
    if (i_reset || i_clear_used)
    begin
      r_used       <= {DMEM_DEPTH{1'b0}};
      r_used_count <= {(DMEM_ADDR_BITS+1){1'b0}};
    end
    else if (w_store && !i_flush_all && !r_used[w_store_addr])
    begin
      r_used[w_store_addr] <= 1'b1;
      r_used_count         <= r_used_count + 1'b1;  // solo palabras nuevas
    end
  end

  // --- Salidas ----------------------------------------------------------------------------
  assign o_pc = r_pc;

  // x[i] = {i, contador}: cada registro distinto y cambia si el nucleo avanza; x0 = 0
  assign o_dbg_reg_data   = (i_dbg_reg_addr == 5'd0) ? {NBIT{1'b0}}
                                                     : {3'b000, i_dbg_reg_addr, r_ciclos};
  assign o_dbg_mem_data   = r_dmem[i_dbg_mem_addr];
  assign o_dbg_mem_used   = r_used[i_dbg_mem_addr];
  assign o_dbg_used_count = r_used_count;

  assign o_stall       = r_ciclos[0];
  assign o_flush_if_id = r_ciclos[1];
  assign o_flush_id_ex = r_ciclos[2];
  assign o_fwd_a       = r_ciclos[4:3];
  assign o_fwd_b       = r_ciclos[6:5];

  // Latches: primer campo de 32 bits = {etiqueta del latch, contador}, el bit valid en su
  // posicion del contrato y el resto en 0. La etiqueta (11/22/33/44) permite ver en el
  // snapshot que cada bloque salio del latch correcto y en el orden de bytes correcto.
  wire [NBIT-1:0] w_instr_if = r_imem[r_pc[IMEM_ADDR_BITS+1:2]];
  wire [NBIT-1:0] w_trace    = (DEBUG_TRACE != 0) ? {8'hEE, r_ciclos} : {NBIT{1'b0}};

  assign o_if_id = {7'd0, r_valid[0], w_instr_if, r_pc + 32'd4, r_pc};

  assign o_id_ex = {w_trace,                 // [247:216] instr
                    15'd0,                   // [215:201] resto de los flags
                    r_valid[1],              // [200] valid
                    168'd0,                  // [199:32]
                    8'h22, r_ciclos};        // [31:0] pc

  assign o_ex_mem = {w_trace,                // [151:120] instr
                     7'd0, r_valid[2],       // [119:112] flags: valid = [112]
                     80'd0,                  // [111:32]
                     8'h33, r_ciclos};       // [31:0] alu_result

  assign o_mem_wb = {w_trace,                // [143:112] instr
                     7'd0, r_valid[3],       // [111:104] flags: valid = [104]
                     72'd0,                  // [103:32]
                     8'h44, r_ciclos};       // [31:0] alu_result

endmodule
