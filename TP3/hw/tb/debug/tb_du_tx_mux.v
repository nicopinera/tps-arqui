`timescale 1ns / 1ps

// Prueba de du_tx_mux (US-403, P1) con la uart_tx real: el byte del canal elegido sale por
// la linea aunque el otro canal tambien pida transmitir, y el o_tx_done le llega solo al
// canal elegido.
module tb_du_tx_mux;
  `include "tb_utils.vh"

  localparam COUNT_MAX = 4;  // baud rapido: 64 ciclos por bit

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  reg        r_sel = 1'b0;
  reg        r_start_0 = 1'b0, r_start_1 = 1'b0;
  reg  [7:0] r_data_0 = 8'h00, r_data_1 = 8'h00;
  wire       w_done_0, w_done_1;
  wire       w_tx_start, w_tx_done, w_s_tick;
  wire [7:0] w_tx_data;

  reg  [7:0] r_dato;
  reg        r_ok;

  du_tx_mux u_mux (
    .i_sel(r_sel),
    .i_start_0(r_start_0), .i_data_0(r_data_0), .o_done_0(w_done_0),
    .i_start_1(r_start_1), .i_data_1(r_data_1), .o_done_1(w_done_1),
    .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done)
  );

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(w_tx_start), .i_din(w_tx_data), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  always #5 clock = ~clock;

  // Los done son pulsos de un ciclo: se cuentan en cada flanco
  integer n_done_0 = 0;
  integer n_done_1 = 0;
  always @(posedge clock)
  begin
    if (w_done_0) n_done_0 = n_done_0 + 1;
    if (w_done_1) n_done_1 = n_done_1 + 1;
  end

  // Los dos canales piden transmitir a la vez; con `sel` solo tiene que salir `esperado`
  task verificar_canal;
    input       sel;
    input [7:0] esperado;
    integer d0_antes, d1_antes;
    begin
      d0_antes = n_done_0;
      d1_antes = n_done_1;
      r_sel = sel;
      fork
        begin
          @(negedge clock);
          r_start_0 = 1'b1;
          r_start_1 = 1'b1;
          @(negedge clock);
          r_start_0 = 1'b0;
          r_start_1 = 1'b0;
          // Bajada del pulso: el posedge de clock que lo cuenta ya paso
          @(negedge w_tx_done);
          @(negedge clock);
        end
        recv_byte(r_dato, r_ok);
      join
      check_eq("byte recibido ok", {31'd0, r_ok}, 32'd1);
      check_eq("sale el dato del canal elegido", {24'd0, r_dato}, {24'd0, esperado});
      check_eq("done al canal 0", n_done_0 - d0_antes, (sel == 1'b0) ? 1 : 0);
      check_eq("done al canal 1", n_done_1 - d1_antes, (sel == 1'b1) ? 1 : 0);
    end
  endtask

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;
    r_data_0 = 8'h3C;
    r_data_1 = 8'hC3;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    // Combinacional: el start del canal no elegido no llega a la UART
    r_sel = 1'b0;
    r_start_1 = 1'b1;
    #1;
    check_eq("sel=0: start1 bloqueado", {31'd0, w_tx_start}, 32'd0);
    check_eq("sel=0: data del canal 0", {24'd0, w_tx_data}, 32'h3C);
    r_start_1 = 1'b0;
    r_sel = 1'b1;
    r_start_0 = 1'b1;
    #1;
    check_eq("sel=1: start0 bloqueado", {31'd0, w_tx_start}, 32'd0);
    check_eq("sel=1: data del canal 1", {24'd0, w_tx_data}, 32'hC3);
    r_start_0 = 1'b0;

    verificar_canal(1'b0, 8'h3C);
    verificar_canal(1'b1, 8'hC3);
    verificar_canal(1'b0, 8'h3C);

    tb_finish;
  end
endmodule
