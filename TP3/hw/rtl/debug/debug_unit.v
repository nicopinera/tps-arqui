`include "du_defs.vh"

// Debug Unit (US-403): interprete de comandos (du_cmd_fsm), respuestas cortas (du_resp_tx) y
// multiplexor de la UART de transmision (du_tx_mux).
//
// Se conecta a la UART del top: recibe los bytes de uart_rx y transmite por uart_tx.
// Los submodulos todavia no existen: sus pedidos (o_req_*) y respuestas (i_*_done) salen como
// puertos para que el testbench los emule. Cada historia mete el suyo adentro y saca esos
// puertos: du_loader (US-404), du_dumper (US-405, canal 1 del mux) y du_exec_ctrl (US-406).
module debug_unit #(
    parameter CLK_FREQ_HZ       = 100_000_000,
    parameter RX_TIMEOUT_CYCLES = CLK_FREQ_HZ / 1000 * `DU_RX_TIMEOUT_MS
  )(
    input  wire        clock,
    input  wire        i_reset,

    // uart_rx
    input  wire        i_rx_done,
    input  wire [7:0]  i_rx_data,
    input  wire        i_parity_err,

    // uart_tx
    output wire        o_tx_start,
    output wire [7:0]  o_tx_data,
    input  wire        i_tx_done,

    // TODO(US-404): du_loader
    output wire        o_req_load,
    output wire        o_load_byte,
    output wire [7:0]  o_load_data,
    output wire        o_load_cancel,
    input  wire        i_load_done,
    input  wire [7:0]  i_load_err,
    output wire        o_req_reset,
    input  wire        i_reset_done,

    // TODO(US-406): du_exec_ctrl y nucleo
    output wire        o_req_run,
    output wire        o_req_step,
    output wire        o_req_abort,
    input  wire        i_step_done,
    input  wire        i_run_fin,
    input  wire        i_halted,
    input  wire        i_illegal,

    // TODO(US-405): du_dumper (transmite por el canal 1 del mux)
    output wire        o_req_dump,
    output wire        o_req_dump_mem,
    output wire [15:0] o_dm_addr,
    output wire [15:0] o_dm_n,
    output wire [7:0]  o_snap_estado,
    input  wire        i_dump_done,
    input  wire [7:0]  i_dump_err,
    input  wire        i_dump_tx_start,
    input  wire [7:0]  i_dump_tx_data,
    output wire        o_dump_tx_done,

    output wire [3:0]  o_estado
  );

  wire       w_resp_send, w_resp_done, w_tx_sel;
  wire [7:0] w_resp_tipo, w_resp_codigo;
  wire       w_start_0, w_done_0;
  wire [7:0] w_data_0;

  du_cmd_fsm #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ), .RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)
  ) u_cmd (
    .clock(clock), .i_reset(i_reset),
    .i_rx_done(i_rx_done), .i_rx_data(i_rx_data), .i_parity_err(i_parity_err),
    .o_resp_send(w_resp_send), .o_resp_tipo(w_resp_tipo), .o_resp_codigo(w_resp_codigo),
    .i_resp_done(w_resp_done),
    .o_tx_sel(w_tx_sel),
    .o_req_load(o_req_load), .o_load_byte(o_load_byte), .o_load_data(o_load_data),
    .o_load_cancel(o_load_cancel), .i_load_done(i_load_done), .i_load_err(i_load_err),
    .o_req_reset(o_req_reset), .i_reset_done(i_reset_done),
    .o_req_run(o_req_run), .o_req_step(o_req_step), .o_req_abort(o_req_abort),
    .i_step_done(i_step_done), .i_run_fin(i_run_fin),
    .i_halted(i_halted), .i_illegal(i_illegal),
    .o_req_dump(o_req_dump), .o_req_dump_mem(o_req_dump_mem),
    .o_dm_addr(o_dm_addr), .o_dm_n(o_dm_n),
    .i_dump_done(i_dump_done), .i_dump_err(i_dump_err), .o_snap_estado(o_snap_estado),
    .o_estado(o_estado)
  );

  du_resp_tx u_resp (
    .clock(clock), .i_reset(i_reset),
    .i_send(w_resp_send), .i_tipo(w_resp_tipo), .i_codigo(w_resp_codigo),
    .o_done(w_resp_done),
    .o_tx_start(w_start_0), .o_tx_data(w_data_0), .i_tx_done(w_done_0)
  );

  du_tx_mux u_mux (
    .i_sel(w_tx_sel),
    .i_start_0(w_start_0), .i_data_0(w_data_0), .o_done_0(w_done_0),
    .i_start_1(i_dump_tx_start), .i_data_1(i_dump_tx_data), .o_done_1(o_dump_tx_done),
    .o_tx_start(o_tx_start), .o_tx_data(o_tx_data), .i_tx_done(i_tx_done)
  );

endmodule
