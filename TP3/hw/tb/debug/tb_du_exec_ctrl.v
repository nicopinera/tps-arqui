`timescale 1ns / 1ps

// Prueba de du_exec_ctrl (US-406) con core_stub (US-402). El testbench hace de du_cmd_fsm
// (pulsos i_req_run / i_req_step) y de du_loader (pulso que limpia el nucleo y el contador).
//
// Dos pares exec + nucleo: A termina con HALT a los 10 ciclos, B con una ilegal a los 7.
// r_sel elige a cual van los pedidos y cuales salidas mira el test.
//
//   AC1  cada STEP: un solo ciclo con o_enable = 1, o_ciclos + 1, PC + 4; o_step_done un
//        ciclo despues, con i_halted ya actualizado
//   AC2  STEP repetido hasta HALTED y RUN terminan con el mismo estado (R-EJ-7)
//   AC6  terminacion por ilegal en ambos modos
//   y ademas: o_run_fin es un nivel que baja con el proximo RUN, i_load_done pone el
//   contador en 0, el nucleo no avanza entre pedidos.
// AC3 (latches con valid = 0) necesita el nucleo real: core_stub no vacia el pipeline al
// terminar. Se verifica en US-411. AC4 es revision de codigo + report_clock_networks.
// AC5 (STEP en HALTED -> NACK) lo resuelve du_cmd_fsm: tb_du_cmd_fsm.
module tb_du_exec_ctrl;
  `include "tb_utils.vh"

  localparam HALT_A = 10;
  localparam HALT_B = 7;

  reg clock = 1'b0;
  reg i_reset = 1'b1;
  reg r_sel = 1'b0;        // 0 = par A, 1 = par B
  reg r_req_run = 1'b0;
  reg r_req_step = 1'b0;
  reg r_load = 1'b0;       // fin de LOAD/RESET: flush_all + clear_used al nucleo, load_done al exec

  always #5 clock = ~clock;

  // --- Par A: HALT a los HALT_A ciclos -----------------------------------------------------
  wire        a_enable, a_stop, a_step_done, a_run_fin, a_halted, a_illegal;
  wire [31:0] a_ciclos, a_pc;
  wire [8:0]  a_used;
  wire [143:0] a_mem_wb;

  du_exec_ctrl u_exec_a (
    .clock(clock), .i_reset(i_reset),
    .i_req_run(r_req_run && !r_sel), .i_req_step(r_req_step && !r_sel), .i_req_abort(1'b0),
    .o_step_done(a_step_done), .o_run_fin(a_run_fin),
    .i_load_done(r_load),
    .i_halted(a_halted), .i_valid(4'b0000), // este tb no usa ABORT (ver tb_du_abort)
    .o_enable(a_enable), .o_stop_fetch(a_stop),
    .o_ciclos(a_ciclos)
  );

  core_stub #(.HALT_AFTER(HALT_A)) u_core_a (
    .clock(clock), .i_reset(i_reset), .i_enable(a_enable),
    .i_flush_all(r_load), .i_stop_fetch(a_stop),
    .o_halted(a_halted), .o_illegal(a_illegal), .o_pc(a_pc),
    .i_imem_we(1'b0), .i_imem_addr(8'd0), .i_imem_wdata(32'd0),
    .i_dbg_dmem_we(1'b0), .i_dbg_dmem_addr(8'd0), .i_clear_used(r_load),
    .i_dbg_reg_addr(5'd0), .o_dbg_reg_data(),
    .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_used(), .o_dbg_used_count(a_used),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(), .o_id_ex(), .o_ex_mem(), .o_mem_wb(a_mem_wb)
  );

  // --- Par B: ilegal a los HALT_B ciclos ---------------------------------------------------
  wire        b_enable, b_stop, b_step_done, b_run_fin, b_halted, b_illegal;
  wire [31:0] b_ciclos, b_pc;
  wire [8:0]  b_used;
  wire [143:0] b_mem_wb;

  du_exec_ctrl u_exec_b (
    .clock(clock), .i_reset(i_reset),
    .i_req_run(r_req_run && r_sel), .i_req_step(r_req_step && r_sel), .i_req_abort(1'b0),
    .o_step_done(b_step_done), .o_run_fin(b_run_fin),
    .i_load_done(r_load),
    .i_halted(b_halted), .i_valid(4'b0000), // este tb no usa ABORT (ver tb_du_abort)
    .o_enable(b_enable), .o_stop_fetch(b_stop),
    .o_ciclos(b_ciclos)
  );

  core_stub #(.HALT_AFTER(HALT_B), .ILLEGAL(1)) u_core_b (
    .clock(clock), .i_reset(i_reset), .i_enable(b_enable),
    .i_flush_all(r_load), .i_stop_fetch(b_stop),
    .o_halted(b_halted), .o_illegal(b_illegal), .o_pc(b_pc),
    .i_imem_we(1'b0), .i_imem_addr(8'd0), .i_imem_wdata(32'd0),
    .i_dbg_dmem_we(1'b0), .i_dbg_dmem_addr(8'd0), .i_clear_used(r_load),
    .i_dbg_reg_addr(5'd0), .o_dbg_reg_data(),
    .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_used(), .o_dbg_used_count(b_used),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(), .o_id_ex(), .o_ex_mem(), .o_mem_wb(b_mem_wb)
  );

  // --- Lo que mira el test: el par elegido -------------------------------------------------
  wire        w_enable    = r_sel ? b_enable    : a_enable;
  wire        w_stop      = r_sel ? b_stop      : a_stop;
  wire        w_step_done = r_sel ? b_step_done : a_step_done;
  wire        w_run_fin   = r_sel ? b_run_fin   : a_run_fin;
  wire        w_halted    = r_sel ? b_halted    : a_halted;
  wire        w_illegal   = r_sel ? b_illegal   : a_illegal;
  wire [31:0] w_ciclos    = r_sel ? b_ciclos    : a_ciclos;
  wire [31:0] w_pc        = r_sel ? b_pc        : a_pc;
  wire [8:0]  w_used      = r_sel ? b_used      : a_used;
  wire [31:0] w_wb        = r_sel ? b_mem_wb[31:0] : a_mem_wb[31:0];  // {8'h44, contador del stub}

  // Flancos con o_enable = 1 (el contador del exec no deberia sumar mas que estos)
  integer n_enable = 0, n_stop = 0;
  always @(posedge clock)
  begin
    if (w_enable) n_enable = n_enable + 1;
    if (w_stop)   n_stop = n_stop + 1;
  end

  // --- Estimulos (en el flanco de bajada, como si vinieran de un registro) ----------------
  task limpiar;                  // lo que hace du_loader al final de LOAD/RESET
    begin
      @(negedge clock) r_load = 1'b1;
      @(negedge clock) r_load = 1'b0;
    end
  endtask

  // Pulso de STEP y espera de o_step_done. Vuelve en el flanco de bajada en que vale 1.
  task step;
    integer espera;
    begin
      @(negedge clock) r_req_step = 1'b1;
      @(negedge clock) r_req_step = 1'b0;
      espera = 1;
      while (!w_step_done && espera < 10)
      begin
        @(negedge clock);
        espera = espera + 1;
      end
      if (!w_step_done)
        tb_timeout("STEP sin o_step_done");
      // Pedido en F0 -> enable entre F0 y F1 -> step_done despues de F1
      check_eq("step_done 2 ciclos tras pedido", espera, 2);
    end
  endtask

  // Pulso de RUN y espera de o_run_fin. Vuelve en el flanco de bajada en que vale 1.
  task correr;
    integer espera;
    begin
      @(negedge clock) r_req_run = 1'b1;
      @(negedge clock) r_req_run = 1'b0;
      check_eq("o_run_fin baja con el pedido", {31'd0, w_run_fin}, 32'd0);
      check_eq("RUN: o_enable en 1", {31'd0, w_enable}, 32'd1);
      espera = 0;
      while (!w_run_fin && espera < 1000)
      begin
        @(negedge clock);
        espera = espera + 1;
      end
      if (!w_run_fin)
        tb_timeout("RUN sin o_run_fin");
    end
  endtask

  // STEP hasta que el nucleo queda halted; devuelve cuantos STEP hicieron falta
  task step_hasta_halted;
    output integer n;
    begin
      n = 0;
      while (!w_halted && n < 50)
      begin
        step;
        n = n + 1;
      end
    end
  endtask

  integer n0, pc0, n_steps;
  reg [31:0] s_ciclos, s_pc, s_wb;
  reg [8:0]  s_used;

  initial
  begin
    tb_init;
    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (2) @(negedge clock);

    check_eq("reset: o_enable", {31'd0, w_enable}, 32'd0);
    check_eq("reset: o_ciclos", w_ciclos, 32'd0);
    check_eq("reset: o_run_fin", {31'd0, w_run_fin}, 32'd0);

    // === AC1: cada STEP es un ciclo ======================================================
    n0  = n_enable;
    pc0 = w_pc;
    step;
    check_eq("STEP: un flanco con enable", n_enable - n0, 1);
    check_eq("STEP: o_ciclos = 1", w_ciclos, 32'd1);
    check_eq("STEP: PC + 4", w_pc, pc0 + 4);
    check_eq("STEP: o_enable ya en 0", {31'd0, w_enable}, 32'd0);
    @(negedge clock);
    check_eq("o_step_done dura un ciclo", {31'd0, w_step_done}, 32'd0);
    step;
    step;
    check_eq("3 STEP: 3 flancos con enable", n_enable - n0, 3);
    check_eq("3 STEP: o_ciclos = 3", w_ciclos, 32'd3);

    // Sin pedidos el nucleo no se mueve
    repeat (30) @(negedge clock);
    check_eq("quieto: sin enable", n_enable - n0, 3);
    check_eq("quieto: o_ciclos", w_ciclos, 32'd3);

    // i_load_done pone el contador en 0
    limpiar;
    check_eq("load_done: o_ciclos = 0", w_ciclos, 32'd0);
    check_eq("load_done: PC = 0", w_pc, 32'd0);

    // === AC2: STEP repetido hasta HALTED ==================================================
    step_hasta_halted(n_steps);
    check_eq("STEP: pasos hasta HALTED", n_steps, HALT_A);
    check_eq("STEP: o_ciclos final", w_ciclos, HALT_A);
    check_eq("STEP: motivo HALT", {31'd0, w_illegal}, 32'd0);
    s_ciclos = w_ciclos;
    s_pc     = w_pc;
    s_wb     = w_wb;
    s_used   = w_used;

    // === AC2: RUN del mismo programa ======================================================
    limpiar;
    n0 = n_enable;
    correr;
    check_eq("RUN: o_enable en 0 al terminar", {31'd0, w_enable}, 32'd0);
    check_eq("RUN = STEP: o_ciclos", w_ciclos, s_ciclos);
    check_eq("RUN = STEP: PC", w_pc, s_pc);
    check_eq("RUN = STEP: MEM/WB", w_wb, s_wb);
    check_eq("RUN = STEP: palabras usadas", {23'd0, w_used}, {23'd0, s_used});
    // El enable baja un ciclo despues de o_halted: ese ciclo de mas no se cuenta
    check_eq("RUN: flancos con enable", n_enable - n0, HALT_A + 1);

    // o_run_fin es un nivel y el nucleo queda quieto
    repeat (50) @(negedge clock);
    check_eq("o_run_fin sigue en 1", {31'd0, w_run_fin}, 32'd1);
    check_eq("despues del RUN: o_ciclos", w_ciclos, s_ciclos);
    check_eq("despues del RUN: sin enable", n_enable - n0, HALT_A + 1);

    // Otro RUN: el o_run_fin viejo baja con el pedido (lo chequea correr) y vuelve a terminar
    limpiar;
    correr;
    check_eq("segundo RUN: o_ciclos", w_ciclos, s_ciclos);

    // === AC6: terminacion por ilegal, en ambos modos =====================================
    r_sel = 1'b1;
    limpiar;
    correr;
    check_eq("RUN ilegal: o_halted", {31'd0, w_halted}, 32'd1);
    check_eq("RUN ilegal: o_illegal", {31'd0, w_illegal}, 32'd1);
    check_eq("RUN ilegal: o_ciclos", w_ciclos, HALT_B);
    limpiar;
    step_hasta_halted(n_steps);
    check_eq("STEP ilegal: pasos", n_steps, HALT_B);
    check_eq("STEP ilegal: o_illegal", {31'd0, w_illegal}, 32'd1);
    check_eq("STEP ilegal: o_ciclos", w_ciclos, HALT_B);

    // ABORT es de US-407: hasta entonces o_stop_fetch nunca se activa
    check_eq("o_stop_fetch siempre en 0", n_stop, 0);

    tb_finish;
  end
endmodule
