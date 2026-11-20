`timescale 1ns / 1ps

// Prueba de ABORT en du_exec_ctrl (US-407) con core_stub. El testbench hace de du_cmd_fsm
// (pulsos i_req_run / i_req_abort) y de du_loader (pulso que limpia el nucleo y el contador).
//
// Dos pares exec + nucleo: A nunca termina (loop infinito), B termina con HALT a los 10 ciclos.
// r_sel elige a cual van los pedidos y cuales salidas mira el test.
//
//   AC1  RUN que nunca termina + ABORT: stop_fetch con enable hasta que los 4 valid son 0,
//        PC congelado, o_run_fin, latches vacios (el snapshot ABORTED lo arma du_cmd_fsm:
//        tb_du_cmd_fsm)
//   y ademas: un HALT que llega a WB durante el drenado lo termina (sin colgarse); ABORT en el
//   mismo ciclo que i_halted no drena; ABORT con el exec en IDLE no hace nada; despues de
//   LOAD se puede volver a correr y abortar.
// AC2 y AC3 (no_halt.asm y el experimento sin relleno) necesitan el nucleo real: US-411.
module tb_du_abort;
  `include "tb_utils.vh"

  localparam HALT_B = 10;

  reg clock = 1'b0;
  reg i_reset = 1'b1;
  reg r_sel = 1'b0;        // 0 = par A, 1 = par B
  reg r_req_run = 1'b0;
  reg r_req_abort = 1'b0;
  reg r_load = 1'b0;       // fin de LOAD/RESET: flush_all + clear_used al nucleo, load_done al exec

  always #5 clock = ~clock;

  // --- Par A: nunca termina ----------------------------------------------------------------
  wire        a_enable, a_stop, a_run_fin, a_halted;
  wire [31:0] a_ciclos, a_pc;
  wire [103:0] a_if_id;
  wire [247:0] a_id_ex;
  wire [151:0] a_ex_mem;
  wire [143:0] a_mem_wb;
  wire [3:0]   a_valid = {a_mem_wb[104], a_ex_mem[112], a_id_ex[200], a_if_id[96]};

  du_exec_ctrl u_exec_a (
    .clock(clock), .i_reset(i_reset),
    .i_req_run(r_req_run && !r_sel), .i_req_step(1'b0), .i_req_abort(r_req_abort && !r_sel),
    .o_step_done(), .o_run_fin(a_run_fin),
    .i_load_done(r_load),
    .i_halted(a_halted), .i_valid(a_valid),
    .o_enable(a_enable), .o_stop_fetch(a_stop),
    .o_ciclos(a_ciclos)
  );

  core_stub u_core_a (
    .clock(clock), .i_reset(i_reset), .i_enable(a_enable),
    .i_flush_all(r_load), .i_stop_fetch(a_stop),
    .o_halted(a_halted), .o_illegal(), .o_pc(a_pc),
    .i_imem_we(1'b0), .i_imem_addr(8'd0), .i_imem_wdata(32'd0),
    .i_dbg_dmem_we(1'b0), .i_dbg_dmem_addr(8'd0), .i_clear_used(r_load),
    .i_dbg_reg_addr(5'd0), .o_dbg_reg_data(),
    .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_used(), .o_dbg_used_count(),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(a_if_id), .o_id_ex(a_id_ex), .o_ex_mem(a_ex_mem), .o_mem_wb(a_mem_wb)
  );

  // --- Par B: HALT a los HALT_B ciclos -----------------------------------------------------
  wire        b_enable, b_stop, b_run_fin, b_halted;
  wire [31:0] b_ciclos, b_pc;
  wire [103:0] b_if_id;
  wire [247:0] b_id_ex;
  wire [151:0] b_ex_mem;
  wire [143:0] b_mem_wb;
  wire [3:0]   b_valid = {b_mem_wb[104], b_ex_mem[112], b_id_ex[200], b_if_id[96]};

  du_exec_ctrl u_exec_b (
    .clock(clock), .i_reset(i_reset),
    .i_req_run(r_req_run && r_sel), .i_req_step(1'b0), .i_req_abort(r_req_abort && r_sel),
    .o_step_done(), .o_run_fin(b_run_fin),
    .i_load_done(r_load),
    .i_halted(b_halted), .i_valid(b_valid),
    .o_enable(b_enable), .o_stop_fetch(b_stop),
    .o_ciclos(b_ciclos)
  );

  core_stub #(.HALT_AFTER(HALT_B)) u_core_b (
    .clock(clock), .i_reset(i_reset), .i_enable(b_enable),
    .i_flush_all(r_load), .i_stop_fetch(b_stop),
    .o_halted(b_halted), .o_illegal(), .o_pc(b_pc),
    .i_imem_we(1'b0), .i_imem_addr(8'd0), .i_imem_wdata(32'd0),
    .i_dbg_dmem_we(1'b0), .i_dbg_dmem_addr(8'd0), .i_clear_used(r_load),
    .i_dbg_reg_addr(5'd0), .o_dbg_reg_data(),
    .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_used(), .o_dbg_used_count(),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(b_if_id), .o_id_ex(b_id_ex), .o_ex_mem(b_ex_mem), .o_mem_wb(b_mem_wb)
  );

  // --- Lo que mira el test: el par elegido -------------------------------------------------
  wire        w_enable  = r_sel ? b_enable  : a_enable;
  wire        w_stop    = r_sel ? b_stop    : a_stop;
  wire        w_run_fin = r_sel ? b_run_fin : a_run_fin;
  wire        w_halted  = r_sel ? b_halted  : a_halted;
  wire [31:0] w_ciclos  = r_sel ? b_ciclos  : a_ciclos;
  wire [31:0] w_pc      = r_sel ? b_pc      : a_pc;
  wire [3:0]  w_valid   = r_sel ? b_valid   : a_valid;

  // Flancos con o_enable = 1 y con o_stop_fetch = 1
  integer n_enable = 0, n_stop = 0;
  always @(posedge clock)
  begin
    if (w_enable) n_enable = n_enable + 1;
    if (w_stop)   n_stop = n_stop + 1;
  end

  // --- Estimulos (en el flanco de bajada, como si vinieran de un registro) ----------------
  task limpiar;
    begin
      @(negedge clock) r_load = 1'b1;
      @(negedge clock) r_load = 1'b0;
    end
  endtask

  task pulso_run;
    begin
      @(negedge clock) r_req_run = 1'b1;
      @(negedge clock) r_req_run = 1'b0;
    end
  endtask

  // Pulso de ABORT en el ciclo actual (llamar en un flanco de bajada)
  task pulso_abort;
    begin
      r_req_abort = 1'b1;
      @(negedge clock) r_req_abort = 1'b0;
    end
  endtask

  task esperar_run_fin;
    integer espera;
    begin
      espera = 0;
      while (!w_run_fin && espera < 100)
      begin
        @(negedge clock);
        espera = espera + 1;
      end
      if (!w_run_fin)
        tb_timeout("ABORT sin o_run_fin (drenado colgado)");
    end
  endtask

  integer s0, e0, pc_drain;

  initial
  begin
    tb_init;
    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (2) @(negedge clock);
    check_eq("reset: o_stop_fetch", {31'd0, w_stop}, 32'd0);

    // === AC1: loop infinito + ABORT ======================================================
    r_sel = 1'b0;
    limpiar;
    pulso_run;
    repeat (20) @(negedge clock);
    check_eq("RUN: corre sin terminar", {31'd0, w_run_fin}, 32'd0);
    check_eq("RUN: pipeline lleno", {28'd0, w_valid}, 32'hF);
    check_eq("RUN: sin stop_fetch", {31'd0, w_stop}, 32'd0);

    s0 = n_stop;
    pulso_abort;
    // Ya en DRAIN: busqueda cortada, pero el nucleo sigue habilitado
    check_eq("DRAIN: stop_fetch = 1", {31'd0, w_stop}, 32'd1);
    check_eq("DRAIN: enable sigue en 1", {31'd0, w_enable}, 32'd1);
    check_eq("DRAIN: todavia sin run_fin", {31'd0, w_run_fin}, 32'd0);
    pc_drain = w_pc;
    esperar_run_fin;
    // 3 ciclos vaciando (1111 -> 1100 -> 1000 -> 0000) + 1 en que el exec ve 0000 y baja
    check_eq("ABORT: 4 flancos con stop_fetch", n_stop - s0, 4);
    check_eq("ABORT: latches vacios", {28'd0, w_valid}, 32'd0);
    check_eq("ABORT: PC congelado", w_pc, pc_drain);
    check_eq("ABORT: enable en 0", {31'd0, w_enable}, 32'd0);
    check_eq("ABORT: stop_fetch en 0", {31'd0, w_stop}, 32'd0);
    check_eq("ABORT: el contador incluye el drenado", w_ciclos, n_enable);

    // Quieto despues del ABORT; run_fin queda en 1 (nivel)
    e0 = n_enable;
    repeat (20) @(negedge clock);
    check_eq("post-ABORT: sin enable", n_enable - e0, 0);
    check_eq("post-ABORT: run_fin sigue en 1", {31'd0, w_run_fin}, 32'd1);

    // ABORT con el exec en IDLE (llego tarde): no hace nada
    s0 = n_stop;
    pulso_abort;
    repeat (5) @(negedge clock);
    check_eq("ABORT en IDLE: sin stop_fetch", n_stop - s0, 0);
    check_eq("ABORT en IDLE: sin enable", n_enable - e0, 0);

    // Despues de LOAD se vuelve a correr y abortar
    limpiar;
    check_eq("LOAD: contador en 0", w_ciclos, 32'd0);
    pulso_run;
    check_eq("RUN 2: run_fin baja", {31'd0, w_run_fin}, 32'd0);
    repeat (10) @(negedge clock);
    pulso_abort;
    esperar_run_fin;
    check_eq("ABORT 2: latches vacios", {28'd0, w_valid}, 32'd0);

    // === HALT que llega a WB durante el drenado ===========================================
    // ABORT con el contador en HALT_B - 2: entra a DRAIN y en el ciclo siguiente el nucleo
    // se detiene con el pipeline a medio vaciar. Sin la condicion de i_halted se colgaria.
    r_sel = 1'b1;
    limpiar;
    pulso_run;
    while (w_ciclos != HALT_B - 2)
      @(negedge clock);
    s0 = n_stop;
    pulso_abort;
    esperar_run_fin;
    check_eq("HALT en drenado: nucleo halted", {31'd0, w_halted}, 32'd1);
    check_eq("HALT en drenado: valid no vacio", {31'd0, (w_valid != 4'b0000)}, 32'd1);
    check_eq("HALT en drenado: 2 flancos con stop_fetch", n_stop - s0, 2);
    check_eq("HALT en drenado: enable en 0", {31'd0, w_enable}, 32'd0);
    check_eq("HALT en drenado: stop_fetch en 0", {31'd0, w_stop}, 32'd0);

    // === ABORT en el mismo ciclo que i_halted: gana el HALT, no hay drenado ===============
    limpiar;
    pulso_run;
    while (!w_halted)
      @(negedge clock);
    s0 = n_stop;
    pulso_abort;            // el exec sigue en RUN y ve i_halted e i_req_abort juntos
    esperar_run_fin;
    check_eq("ABORT + HALT juntos: sin stop_fetch", n_stop - s0, 0);
    check_eq("ABORT + HALT juntos: ciclos = HALT_B", w_ciclos, HALT_B);

    tb_finish;
  end

endmodule
