`timescale 1ns / 1ps

// Prueba de DUMP_MEM (US-408) de punta a punta, como en la placa:
//   host model -> uart_rx -> debug_unit (con du_dumper real) -> uart_tx -> host model
// El nucleo es un core_stub que nunca termina; su DMEM se carga desde el testbench.
//
//   AC1  DUMP_MEM 0x000, 4 devuelve las 4 primeras palabras de la DMEM
//   AC2  un rango que se sale de la DMEM (o no alineado, o n = 0, o n = FFFF) responde
//        NACK(ERR_RANGO) y el estado no cambia
//   AC3  DUMP_MEM en RUN responde NACK(ERR_ESTADO)
//   AC4  los ejemplos de protocolo.md 8.9 salen byte a byte (MEM_DATA y NACK)
//   y ademas: DUMP_MEM en IDLE, READY y HALTED vuelve al mismo estado; en HALTED lee lo que
//   escribio el programa; toda la DMEM (256 palabras) en una trama.
module tb_du_dump_mem;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam COUNT_MAX = 4;     // baud rapido: 64 ciclos por bit
  localparam TIMEOUT   = 3000;

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  // --- UART + Debug Unit + core_stub ----------------------------------------------------------
  wire       w_s_tick, w_rx_done, w_parity_err, w_tx_start, w_tx_done;
  wire [7:0] w_rx_data, w_tx_data;
  wire [3:0] w_estado;

  wire        w_imem_we, w_dmem_we, w_clear_used, w_flush_all, w_enable, w_stop_fetch;
  wire [7:0]  w_imem_addr, w_dmem_addr, w_mem_addr;
  wire [31:0] w_imem_wdata, w_pc, w_reg_data, w_mem_data;
  wire [4:0]  w_reg_addr;
  wire        w_mem_used, w_stall, w_fl_ifid, w_fl_idex;
  wire [8:0]  w_used_count;
  wire [1:0]  w_fwd_a, w_fwd_b;
  wire [103:0] w_if_id;
  wire [247:0] w_id_ex;
  wire [151:0] w_ex_mem;
  wire [143:0] w_mem_wb;

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_rx u_rx (
    .clock(clock), .i_reset(i_reset), .rx(host_tx), .i_s_tick(w_s_tick),
    .o_rx_done(w_rx_done), .o_parity_err(w_parity_err), .o_dout(w_rx_data)
  );

  debug_unit #(.RX_TIMEOUT_CYCLES(TIMEOUT)) u_du (
    .clock(clock), .i_reset(i_reset),
    .i_rx_done(w_rx_done), .i_rx_data(w_rx_data), .i_parity_err(w_parity_err),
    .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done),
    .o_imem_we(w_imem_we), .o_imem_addr(w_imem_addr), .o_imem_wdata(w_imem_wdata),
    .o_dmem_we(w_dmem_we), .o_dmem_addr(w_dmem_addr),
    .o_clear_used(w_clear_used), .o_flush_all(w_flush_all),
    .o_enable(w_enable), .o_stop_fetch(w_stop_fetch),
    .i_halted(1'b0), .i_illegal(1'b0),
    .i_pc(w_pc), .o_dbg_reg_addr(w_reg_addr), .i_dbg_reg_data(w_reg_data),
    .o_dbg_mem_addr(w_mem_addr), .i_dbg_mem_data(w_mem_data), .i_dbg_mem_used(w_mem_used),
    .i_dbg_used_count(w_used_count),
    .i_stall(w_stall), .i_flush_if_id(w_fl_ifid), .i_flush_id_ex(w_fl_idex),
    .i_fwd_a(w_fwd_a), .i_fwd_b(w_fwd_b),
    .i_if_id(w_if_id), .i_id_ex(w_id_ex), .i_ex_mem(w_ex_mem), .i_mem_wb(w_mem_wb),
    .o_estado(w_estado)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(w_tx_start), .i_din(w_tx_data), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  core_stub u_core (
    .clock(clock), .i_reset(i_reset), .i_enable(w_enable),
    .i_flush_all(w_flush_all), .i_stop_fetch(w_stop_fetch),
    .o_halted(), .o_illegal(), .o_pc(w_pc),
    .i_imem_we(w_imem_we), .i_imem_addr(w_imem_addr), .i_imem_wdata(w_imem_wdata),
    .i_dbg_dmem_we(w_dmem_we), .i_dbg_dmem_addr(w_dmem_addr), .i_clear_used(w_clear_used),
    .i_dbg_reg_addr(w_reg_addr), .o_dbg_reg_data(w_reg_data),
    .i_dbg_mem_addr(w_mem_addr), .o_dbg_mem_data(w_mem_data), .o_dbg_mem_used(w_mem_used),
    .o_dbg_used_count(w_used_count),
    .o_stall(w_stall), .o_flush_if_id(w_fl_ifid), .o_flush_id_ex(w_fl_idex),
    .o_fwd_a(w_fwd_a), .o_fwd_b(w_fwd_b),
    .o_if_id(w_if_id), .o_id_ex(w_id_ex), .o_ex_mem(w_ex_mem), .o_mem_wb(w_mem_wb)
  );

  always #5 clock = ~clock;

  // --- Tareas del host ----------------------------------------------------------------------
  reg r_ok;

  // Manda cmd + n_args bytes de host_args y recibe la trama de respuesta (como tb_du_cmd_fsm)
  task enviar;
    input [7:0]   cmd;
    input integer n_args;
    begin
      fork
        send_cmd(cmd, n_args);
        begin
          repeat (n_args * 11 * host_ciclos_bit) @(negedge clock);
          recv_frame(r_ok);
        end
      join
      repeat (3 * host_ciclos_bit) @(negedge clock);
    end
  endtask

  task args_dm;
    input [15:0] addr;
    input [15:0] n;
    begin
      host_args[0] = addr[7:0];
      host_args[1] = addr[15:8];
      host_args[2] = n[7:0];
      host_args[3] = n[15:8];
    end
  endtask

  // Bytes crudos de la respuesta, sin interpretar: para comparar contra protocolo.md
  reg [7:0] crudo [0:31];
  task enviar_crudo;
    input integer n_bytes;
    integer i;
    reg     ok;
    begin
      fork
        send_cmd(`DU_CMD_DUMP_MEM, 4);
        begin
          repeat (4 * 11 * host_ciclos_bit) @(negedge clock);
          for (i = 0; i < n_bytes; i = i + 1)
            recv_byte(crudo[i], ok);
        end
      join
      repeat (3 * host_ciclos_bit) @(negedge clock);
    end
  endtask

  function [31:0] palabra_payload;
    input integer off;
    palabra_payload = {host_payload[off+3], host_payload[off+2],
                       host_payload[off+1], host_payload[off]};
  endfunction

  // DUMP_MEM valido: MEM_DATA con las palabras de la DMEM del stub, y el estado no cambia
  task dump_mem_ok;
    input [8*24-1:0] nombre;
    input [15:0]     addr;
    input [15:0]     n;
    input [3:0]      estado;
    integer i, n_mal;
    begin
      args_dm(addr, n);
      enviar(`DU_CMD_DUMP_MEM, 4);
      check_eq(nombre, {31'd0, r_ok}, 32'd1);
      check_eq(nombre, {24'd0, host_tipo}, {24'd0, `DU_TIPO_MEM_DATA});
      check_eq(nombre, {16'd0, host_len}, 32'd4 + 32'd4 * n);
      check_eq(nombre, {16'd0, host_payload[1], host_payload[0]}, {16'd0, addr});
      check_eq(nombre, {16'd0, host_payload[3], host_payload[2]}, {16'd0, n});
      n_mal = 0;
      for (i = 0; i < n; i = i + 1)
        if (palabra_payload(4 + 4 * i) !== u_core.r_dmem[addr[9:2] + i])
        begin
          if (n_mal == 0)
            $display("  palabra %0d: llego 0x%08h, DMEM 0x%08h", i, palabra_payload(4 + 4 * i),
                     u_core.r_dmem[addr[9:2] + i]);
          n_mal = n_mal + 1;
        end
      check_eq(nombre, n_mal, 0);
      check_eq(nombre, {28'd0, w_estado}, {28'd0, estado});
    end
  endtask

  // DUMP_MEM rechazado: NACK con el codigo, y el estado no cambia
  task dump_mem_nack;
    input [8*24-1:0] nombre;
    input [15:0]     addr;
    input [15:0]     n;
    input [7:0]      codigo;
    input [3:0]      estado;
    begin
      args_dm(addr, n);
      enviar(`DU_CMD_DUMP_MEM, 4);
      check_eq(nombre, {31'd0, r_ok}, 32'd1);
      check_eq(nombre, {24'd0, host_tipo}, {24'd0, `DU_TIPO_NACK});
      check_eq(nombre, {24'd0, host_payload[0]}, {24'd0, codigo});
      check_eq(nombre, {28'd0, w_estado}, {28'd0, estado});
    end
  endtask

  integer i;

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;
    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    // DMEM conocida: palabra a = {A0, a, ~a, 5A}
    for (i = 0; i < 256; i = i + 1)
      u_core.r_dmem[i] = {8'hA0, i[7:0], ~i[7:0], 8'h5A};

    // === IDLE (sin programa): DUMP_MEM vale y vuelve a IDLE =================================
    dump_mem_ok("AC1: 0x000, 4", 16'h0000, 16'd4, `DU_ESTADO_IDLE);
    dump_mem_ok("ultima palabra", 16'h03FC, 16'd1, `DU_ESTADO_IDLE);
    dump_mem_ok("toda la DMEM", 16'h0000, 16'd256, `DU_ESTADO_IDLE);

    // AC2: fuera de rango, NACK(ERR_RANGO) y el estado no cambia
    dump_mem_nack("se pasa del final", 16'h03FC, 16'd2, `DU_ERR_RANGO, `DU_ESTADO_IDLE);
    dump_mem_nack("no alineada", 16'h0006, 16'd1, `DU_ERR_RANGO, `DU_ESTADO_IDLE);
    dump_mem_nack("n = 0", 16'h0000, 16'd0, `DU_ERR_RANGO, `DU_ESTADO_IDLE);
    dump_mem_nack("n = FFFF", 16'h0004, 16'hFFFF, `DU_ERR_RANGO, `DU_ESTADO_IDLE);
    dump_mem_nack("dir 0x400", 16'h0400, 16'd1, `DU_ERR_RANGO, `DU_ESTADO_IDLE);

    // === AC4: los ejemplos de protocolo.md 8.9, byte a byte ===================================
    u_core.r_dmem[0] = 32'd5;
    u_core.r_dmem[1] = 32'd0;
    args_dm(16'h0000, 16'd2);
    enviar_crudo(17);
    check_eq("8.9 MEM_DATA bytes 0-3", {crudo[0], crudo[1], crudo[2], crudo[3]}, 32'hA5_05_0C_00);
    check_eq("8.9 MEM_DATA bytes 4-7", {crudo[4], crudo[5], crudo[6], crudo[7]}, 32'h00_00_02_00);
    check_eq("8.9 MEM_DATA bytes 8-11", {crudo[8], crudo[9], crudo[10], crudo[11]}, 32'h05_00_00_00);
    check_eq("8.9 MEM_DATA bytes 12-15", {crudo[12], crudo[13], crudo[14], crudo[15]}, 32'h00_00_00_00);
    check_eq("8.9 MEM_DATA checksum", {24'd0, crudo[16]}, 32'h0E);
    args_dm(16'h03FC, 16'd2);
    enviar_crudo(6);
    check_eq("8.9 NACK bytes 0-3", {crudo[0], crudo[1], crudo[2], crudo[3]}, 32'hA5_02_01_00);
    check_eq("8.9 NACK bytes 4-5", {16'd0, crudo[4], crudo[5]}, 32'h0000_0506);
    check_eq("8.9 NACK: sigue en IDLE", {28'd0, w_estado}, {28'd0, `DU_ESTADO_IDLE});

    // === READY ===============================================================================
    // LOAD de una palabra (N = 1, addi x1, x0, 5, checksum): el loader limpia la DMEM
    host_args[0] = 8'h01; host_args[1] = 8'h00;
    host_args[2] = 8'h93; host_args[3] = 8'h00; host_args[4] = 8'h50; host_args[5] = 8'h00;
    host_args[6] = 8'h01 ^ 8'h93 ^ 8'h50;
    enviar(`DU_CMD_LOAD, 7);
    check_eq("LOAD: ACK", {24'd0, host_tipo}, {24'd0, `DU_TIPO_ACK});
    check_eq("LOAD: READY", {28'd0, w_estado}, {28'd0, `DU_ESTADO_READY});
    dump_mem_ok("READY: DMEM limpia", 16'h0010, 16'd4, `DU_ESTADO_READY);
    check_eq("READY: palabra 4 en 0", u_core.r_dmem[4], 32'd0);
    dump_mem_nack("READY: fuera de rango", 16'h03F0, 16'd5, `DU_ERR_RANGO, `DU_ESTADO_READY);

    // === AC3: en RUN responde NACK(ERR_ESTADO). Solo el comando: en RUN los argumentos se
    // interpretarian como comandos (protocolo.md 5)
    enviar(`DU_CMD_RUN, 0);
    check_eq("RUN: ACK", {24'd0, host_tipo}, {24'd0, `DU_TIPO_ACK});
    enviar(`DU_CMD_DUMP_MEM, 0);
    check_eq("AC3: NACK", {24'd0, host_tipo}, {24'd0, `DU_TIPO_NACK});
    check_eq("AC3: ERR_ESTADO", {24'd0, host_payload[0]}, {24'd0, `DU_ERR_ESTADO});
    check_eq("AC3: sigue en RUN", {28'd0, w_estado}, {28'd0, `DU_ESTADO_RUN});

    // ABORT -> snapshot ABORTED -> HALTED
    enviar(`DU_CMD_ABORT, 0);
    check_eq("ABORT: SNAPSHOT", {24'd0, host_tipo}, {24'd0, `DU_TIPO_SNAPSHOT});
    check_eq("ABORT: HALTED", {28'd0, w_estado}, {28'd0, `DU_ESTADO_HALTED});

    // === HALTED: lo que escribio el "programa" (el stub guarda {D0, ciclos} cada 4 ciclos)
    check_eq("el programa escribio", {31'd0, (w_used_count != 9'd0)}, 32'd1);
    dump_mem_ok("HALTED: 8 palabras", 16'h0000, 16'd8, `DU_ESTADO_HALTED);
    check_eq("HALTED: palabra 1 escrita", {24'd0, u_core.r_dmem[1][31:24]}, 32'hD0);
    dump_mem_nack("HALTED: no alineada", 16'h0001, 16'd1, `DU_ERR_RANGO, `DU_ESTADO_HALTED);

    tb_finish;
  end
endmodule
