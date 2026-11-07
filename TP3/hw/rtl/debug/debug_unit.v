// Debug Unit (US-403): por ahora el interprete de comandos con las respuestas cortas.
// Se conecta a la UART del top: recibe los bytes de uart_rx y transmite por uart_tx.
// Cada historia agrega su submodulo: du_loader (US-404), du_dumper (US-405, canal 1 del
// mux) y du_exec_ctrl (US-406).
module debug_unit (
    input  wire       clock,
    input  wire       i_reset,

    // uart_rx
    input  wire       i_rx_done,
    input  wire [7:0] i_rx_data,

    // uart_tx
    output wire       o_tx_start,
    output wire [7:0] o_tx_data,
    input  wire       i_tx_done,

    output wire [3:0] o_estado
  );

  wire       w_resp_send, w_resp_done;
  wire [7:0] w_resp_tipo, w_resp_codigo;
  wire       w_start_0, w_done_0;
  wire [7:0] w_data_0;

  du_cmd_fsm u_cmd (
    .clock(clock), .i_reset(i_reset),
    .i_rx_done(i_rx_done), .i_rx_data(i_rx_data),
    .o_resp_send(w_resp_send), .o_resp_tipo(w_resp_tipo), .o_resp_codigo(w_resp_codigo),
    .i_resp_done(w_resp_done),
    .o_estado(o_estado)
  );

  du_resp_tx u_resp (
    .clock(clock), .i_reset(i_reset),
    .i_send(w_resp_send), .i_tipo(w_resp_tipo), .i_codigo(w_resp_codigo),
    .o_done(w_resp_done),
    .o_tx_start(w_start_0), .o_tx_data(w_data_0), .i_tx_done(w_done_0)
  );

  // TODO(US-405): canal 1 = du_dumper, e i_sel lo maneja du_cmd_fsm
  // verilator lint_off PINCONNECTEMPTY
  du_tx_mux u_mux (
    .i_sel(1'b0),
    .i_start_0(w_start_0), .i_data_0(w_data_0), .o_done_0(w_done_0),
    .i_start_1(1'b0), .i_data_1(8'h00), .o_done_1(),
    .o_tx_start(o_tx_start), .o_tx_data(o_tx_data), .i_tx_done(i_tx_done)
  );
  // verilator lint_on PINCONNECTEMPTY

endmodule
