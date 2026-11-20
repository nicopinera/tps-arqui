`timescale 1ns / 1ps

// Prueba del nucleo stub (US-402): que respete la semantica del contrato de riscv_core
// (docs/interfaces/riscv_core.md) que la Debug Unit va a usar: enable, congelado, IMEM,
// DMEM con bitmap, drenado con stop_fetch, flush_all, clear_used, terminacion y layout de
// los bits valid en los buses de latches.
module tb_core_stub;
  `include "tb_utils.vh"

  reg clock = 1'b0;
  reg i_reset = 1'b1;
  reg r_enable = 1'b0;
  reg r_flush = 1'b0;
  reg r_stop = 1'b0;
  reg r_imem_we = 1'b0;
  reg [7:0]  r_imem_addr = 8'd0;
  reg [31:0] r_imem_wdata = 32'd0;
  reg r_dbg_dmem_we = 1'b0;
  reg [7:0] r_dbg_dmem_addr = 8'd0;
  reg r_clear_used = 1'b0;
  reg [4:0] r_reg_addr = 5'd0;
  reg [7:0] r_mem_addr = 8'd0;

  // Salidas del stub que no termina nunca (u_core)
  wire        w_halted, w_illegal;
  wire [31:0] w_pc, w_reg_data, w_mem_data;
  wire        w_mem_used;
  wire [8:0]  w_used_count;
  wire        w_stall, w_flush_if_id, w_flush_id_ex;
  wire [1:0]  w_fwd_a, w_fwd_b;
  wire [103:0] w_if_id;
  wire [247:0] w_id_ex;
  wire [151:0] w_ex_mem;
  wire [143:0] w_mem_wb;

  // Salidas del stub que termina por ilegal a los 10 ciclos (u_halt)
  wire        w_h_halted, w_h_illegal;
  wire [31:0] w_h_pc;

  // Los 4 bits valid en las posiciones del contrato (seccion 4)
  wire [3:0] w_valid = {w_mem_wb[104], w_ex_mem[112], w_id_ex[200], w_if_id[96]};

  core_stub u_core (
    .clock(clock), .i_reset(i_reset), .i_enable(r_enable), .i_flush_all(r_flush),
    .i_stop_fetch(r_stop), .o_halted(w_halted), .o_illegal(w_illegal), .o_pc(w_pc),
    .i_imem_we(r_imem_we), .i_imem_addr(r_imem_addr), .i_imem_wdata(r_imem_wdata),
    .i_dbg_dmem_we(r_dbg_dmem_we), .i_dbg_dmem_addr(r_dbg_dmem_addr),
    .i_clear_used(r_clear_used),
    .i_dbg_reg_addr(r_reg_addr), .o_dbg_reg_data(w_reg_data),
    .i_dbg_mem_addr(r_mem_addr), .o_dbg_mem_data(w_mem_data), .o_dbg_mem_used(w_mem_used),
    .o_dbg_used_count(w_used_count),
    .o_stall(w_stall), .o_flush_if_id(w_flush_if_id), .o_flush_id_ex(w_flush_id_ex),
    .o_fwd_a(w_fwd_a), .o_fwd_b(w_fwd_b),
    .o_if_id(w_if_id), .o_id_ex(w_id_ex), .o_ex_mem(w_ex_mem), .o_mem_wb(w_mem_wb)
  );

  core_stub #(.HALT_AFTER(10), .ILLEGAL(1)) u_halt (
    .clock(clock), .i_reset(i_reset), .i_enable(r_enable), .i_flush_all(r_flush),
    .i_stop_fetch(r_stop), .o_halted(w_h_halted), .o_illegal(w_h_illegal), .o_pc(w_h_pc),
    .i_imem_we(r_imem_we), .i_imem_addr(r_imem_addr), .i_imem_wdata(r_imem_wdata),
    .i_dbg_dmem_we(r_dbg_dmem_we), .i_dbg_dmem_addr(r_dbg_dmem_addr),
    .i_clear_used(r_clear_used),
    .i_dbg_reg_addr(r_reg_addr), .o_dbg_reg_data(),
    .i_dbg_mem_addr(r_mem_addr), .o_dbg_mem_data(), .o_dbg_mem_used(),
    .o_dbg_used_count(),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(), .o_id_ex(), .o_ex_mem(), .o_mem_wb()
  );

  always #5 clock = ~clock;

  // n ciclos con i_enable = 1 (como n STEP seguidos)
  task avanzar;
    input integer n;
    begin
      r_enable = 1'b1;
      repeat (n) @(negedge clock);
      r_enable = 1'b0;
    end
  endtask

  task escribir_imem;
    input [7:0]  addr;
    input [31:0] dato;
    begin
      r_imem_addr  = addr;
      r_imem_wdata = dato;
      r_imem_we    = 1'b1;
      @(negedge clock);
      r_imem_we    = 1'b0;
    end
  endtask

  reg [31:0] r_pc_antes, r_reg_antes;
  reg [8:0]  r_count_antes;

  initial
  begin
    tb_init;
    repeat (4) @(negedge clock);
    i_reset = 1'b0;

    // 1. Despues del reset todo arranca en cero
    check_eq("reset: pc", w_pc, 32'd0);
    check_eq("reset: halted", {31'd0, w_halted}, 32'd0);
    check_eq("reset: valid", {28'd0, w_valid}, 32'd0);
    check_eq("reset: palabras usadas", {23'd0, w_used_count}, 32'd0);

    // 2. LOAD: la IMEM se escribe con el nucleo congelado y el PC no se mueve
    escribir_imem(8'd0, 32'hDEADBEEF);
    escribir_imem(8'd1, 32'hCAFEF00D);
    check_eq("IMEM: pc sigue en 0", w_pc, 32'd0);
    check_eq("IF/ID instr = IMEM[0]", w_if_id[95:64], 32'hDEADBEEF);

    // 3. Un STEP: el PC avanza 4 y entra la primera instruccion valida a IF/ID
    avanzar(1);
    check_eq("STEP: pc", w_pc, 32'd4);
    check_eq("IF/ID pc", w_if_id[31:0], 32'd4);
    check_eq("IF/ID pc_plus4", w_if_id[63:32], 32'd8);
    check_eq("IF/ID instr = IMEM[1]", w_if_id[95:64], 32'hCAFEF00D);
    check_eq("valid tras 1 ciclo", {28'd0, w_valid}, 32'b0001);

    // 4. Cuatro ciclos mas: el pipeline se llena y hubo 2 stores (ciclos 0 y 4)
    avanzar(4);
    check_eq("pc tras 5 ciclos", w_pc, 32'd20);
    check_eq("valid con el pipeline lleno", {28'd0, w_valid}, 32'b1111);
    check_eq("palabras usadas", {23'd0, w_used_count}, 32'd2);
    r_mem_addr = 8'd1;
    #1;
    check_eq("DMEM[1] = store del ciclo 4", w_mem_data, 32'hD0000004);
    check_eq("DMEM[1] marcada como usada", {31'd0, w_mem_used}, 32'd1);

    // 5. Congelado: con i_enable = 0 no cambia nada aunque pasen ciclos
    r_reg_addr = 5'd5;
    #1;
    r_pc_antes  = w_pc;
    r_reg_antes = w_reg_data;
    check_eq("x5 = {5, contador}", w_reg_data, 32'h05000005);
    repeat (10) @(negedge clock);
    check_eq("congelado: pc", w_pc, r_pc_antes);
    check_eq("congelado: x5", w_reg_data, r_reg_antes);
    r_reg_addr = 5'd0;
    #1;
    check_eq("x0 = 0", w_reg_data, 32'd0);

    // 6. Etiquetas de los latches: cada bloque sale del latch correcto
    check_eq("ID/EX: etiqueta 22", {24'd0, w_id_ex[31:24]}, 32'h22);
    check_eq("EX/MEM: etiqueta 33", {24'd0, w_ex_mem[31:24]}, 32'h33);
    check_eq("MEM/WB: etiqueta 44", {24'd0, w_mem_wb[31:24]}, 32'h44);
    check_eq("ID/EX instr (DEBUG_TRACE)", w_id_ex[247:216], 32'hEE000005);

    // 7. Limpieza de DMEM: la palabra queda en 0 pero el bitmap no se toca
    r_dbg_dmem_addr = 8'd1;
    r_dbg_dmem_we   = 1'b1;
    @(negedge clock);
    r_dbg_dmem_we   = 1'b0;
    check_eq("limpieza: DMEM[1] = 0", w_mem_data, 32'd0);
    check_eq("limpieza: sigue marcada", {31'd0, w_mem_used}, 32'd1);
    check_eq("limpieza: contador igual", {23'd0, w_used_count}, 32'd2);

    // 8. ABORT: con stop_fetch el PC se congela y el pipeline se vacia
    r_pc_antes = w_pc;
    r_stop = 1'b1;
    avanzar(4);
    r_stop = 1'b0;
    check_eq("stop_fetch: pc congelado", w_pc, r_pc_antes);
    check_eq("stop_fetch: pipeline vacio", {28'd0, w_valid}, 32'd0);

    // 9. flush_all actua con el nucleo congelado y no borra la memoria usada
    r_count_antes = w_used_count;
    r_flush = 1'b1;
    @(negedge clock);
    r_flush = 1'b0;
    check_eq("flush_all: pc", w_pc, 32'd0);
    check_eq("flush_all: valid", {28'd0, w_valid}, 32'd0);
    check_eq("flush_all: contador intacto", {23'd0, w_used_count}, {23'd0, r_count_antes});

    // 10. clear_used borra bitmap y contador
    r_clear_used = 1'b1;
    @(negedge clock);
    r_clear_used = 1'b0;
    check_eq("clear_used: contador", {23'd0, w_used_count}, 32'd0);
    check_eq("clear_used: bitmap", {31'd0, w_mem_used}, 32'd0);

    // 11. Terminacion: u_halt termina por ilegal a los 10 ciclos y despues ignora enable
    i_reset = 1'b1;
    @(negedge clock);
    i_reset = 1'b0;
    avanzar(9);
    check_eq("9 ciclos: todavia no termino", {31'd0, w_h_halted}, 32'd0);
    avanzar(1);
    check_eq("10 ciclos: halted", {31'd0, w_h_halted}, 32'd1);
    check_eq("10 ciclos: illegal", {31'd0, w_h_illegal}, 32'd1);
    r_pc_antes = w_h_pc;
    avanzar(5);
    check_eq("halted ignora enable", w_h_pc, r_pc_antes);
    check_eq("HALT_AFTER = 0 no termina", {31'd0, w_halted}, 32'd0);
    r_flush = 1'b1;
    @(negedge clock);
    r_flush = 1'b0;
    check_eq("flush_all limpia halted", {31'd0, w_h_halted}, 32'd0);

    tb_finish;
  end
endmodule
