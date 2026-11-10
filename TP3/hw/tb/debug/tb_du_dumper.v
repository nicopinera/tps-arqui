`timescale 1ns / 1ps

// Prueba de du_dumper (US-405) con du_tx_mux (canal 1) y uart_tx reales.
//
// P2: solo el sobre de la trama (todavia sin payload): A5 03 len_lo len_hi XOR, con
// longitud = 221 + 6K fijada al pedir el volcado, o_done de un pulso y o_tx_start que nunca
// dura mas de un ciclo. En P7 este testbench crece con core_stub y el decodificador completo.
module tb_du_dumper;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam COUNT_MAX = 4;  // baud rapido: 64 ciclos por bit

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  reg        r_req = 1'b0;
  reg  [8:0] r_used_count = 9'd0;  // K que ve el dumper
  wire       w_done;
  wire [7:0] w_err;
  wire       w_start_1, w_done_1, w_tx_start, w_tx_done, w_s_tick;
  wire [7:0] w_data_1, w_tx_data;

  // verilator lint_off PINCONNECTEMPTY
  du_dumper u_dump (
    .clock(clock), .i_reset(i_reset),
    .i_req_dump(r_req), .i_snap_estado(8'h04), .o_done(w_done), .o_err(w_err),
    .i_ciclos(32'd0), .i_pc(32'd0),
    .o_dbg_reg_addr(), .i_dbg_reg_data(32'd0),
    .o_dbg_mem_addr(), .i_dbg_mem_data(32'd0), .i_dbg_mem_used(1'b0),
    .i_dbg_used_count(r_used_count),
    .i_stall(1'b0), .i_flush_if_id(1'b0), .i_flush_id_ex(1'b0),
    .i_fwd_a(2'b00), .i_fwd_b(2'b00),
    .i_if_id(104'd0), .i_id_ex(248'd0), .i_ex_mem(152'd0), .i_mem_wb(144'd0),
    .o_tx_start(w_start_1), .o_tx_data(w_data_1), .i_tx_done(w_done_1)
  );

  du_tx_mux u_mux (
    .i_sel(1'b1),
    .i_start_0(1'b0), .i_data_0(8'h00), .o_done_0(),
    .i_start_1(w_start_1), .i_data_1(w_data_1), .o_done_1(w_done_1),
    .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done)
  );
  // verilator lint_on PINCONNECTEMPTY

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(w_tx_start), .i_din(w_tx_data), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  always #5 clock = ~clock;

  // Monitores: pulsos de o_done y starts de mas de un ciclo
  integer n_done = 0;
  integer n_start_largo = 0;
  reg     r_start_ant = 1'b0;
  always @(posedge clock)
  begin
    if (w_done)
      n_done = n_done + 1;
    if (w_start_1 && r_start_ant)
      n_start_largo = n_start_largo + 1;
    r_start_ant = w_start_1;
  end

  // Pulso de i_req_dump con K = k; despues K cambia: la longitud tiene que ser la del pedido
  task pedir;
    input [8:0] k;
    begin
      @(negedge clock);
      r_used_count = k;
      r_req        = 1'b1;
      @(negedge clock);
      r_req        = 1'b0;
      r_used_count = 9'd77;
    end
  endtask

  // Recibe un byte y lo compara
  task esperar_byte;
    input [255:0] nombre;
    input [7:0]   esperado;
    reg   [7:0]   b;
    reg           ok;
    begin
      recv_byte(b, ok);
      check_eq("byte recibido sin error", {31'd0, ok}, 32'd1);
      check_eq(nombre, {24'd0, b}, {24'd0, esperado});
    end
  endtask

  // Pide un volcado con K y verifica el sobre completo
  task verificar;
    input [8:0] k;
    reg   [15:0] len;
    integer done_antes;
    begin
      len        = 16'd221 + 16'd6 * {7'd0, k};
      done_antes = n_done;
      fork
        pedir(k);
        begin
          esperar_byte("sync A5", `DU_SYNC);
          esperar_byte("tipo SNAPSHOT", `DU_TIPO_SNAPSHOT);
          esperar_byte("len_lo", len[7:0]);
          esperar_byte("len_hi", len[15:8]);
          esperar_byte("checksum", `DU_TIPO_SNAPSHOT ^ len[7:0] ^ len[15:8]);
        end
      join
      repeat (4 * host_ciclos_bit) @(negedge clock);  // el o_done llega tras el STOP
      check_eq("o_done: un solo pulso", n_done - done_antes, 1);
      check_eq("o_err en 0", {24'd0, w_err}, 32'd0);
    end
  endtask

  reg [7:0] r_b;
  reg       r_ok;

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    verificar(9'd0);    // AC3: len 221 = DD 00
    verificar(9'd2);    // len 233 = E9 00
    verificar(9'd256);  // memoria llena: len 1757 = DD 06

    check_eq("o_tx_start nunca dura 2 ciclos", n_start_largo, 0);

    // Sin pedido no sale nada
    recv_byte(r_b, r_ok);
    check_eq("sin pedido no sale nada", {31'd0, r_ok}, 32'd0);

    tb_finish;
  end
endmodule
