module uart_rx #(
    parameter NBIT   = 8,
    parameter N_TICK = 16
  )(
    input  wire clock,
    input  wire i_reset,
    input  wire rx,
    input  wire i_s_tick,
    output wire o_rx_done,
    output wire o_parity_err,
    output wire [NBIT-1:0] o_dout
  );

  wire w_s_clr, w_n_clr, w_n_incr, w_b_shift, w_p_load;
  wire [3:0] w_s_reg;
  wire [2:0] w_n_reg;
  wire [NBIT-1:0] w_b_reg;
  wire w_p_reg; // registro para almacenar la paridad
  wire w_rx_done_fsm;
  wire w_error;

  uart_rx_fsm #(
                .NBIT(NBIT),
                .N_TICK(N_TICK)
              ) fsm (
                .clock(clock),
                .i_reset(i_reset),
                .rx(rx),
                .i_s_tick(i_s_tick),
                .i_s_reg(w_s_reg),
                .i_n_reg(w_n_reg),
                .o_s_clr(w_s_clr),
                .o_n_clr(w_n_clr),
                .o_n_incr(w_n_incr),
                .o_b_shift(w_b_shift),
                .o_p_load(w_p_load),
                .o_rx_done(w_rx_done_fsm)
              );

  uart_rx_datapath #(
                     .NBIT(NBIT)
                   ) datapath (
                     .clock(clock),
                     .i_reset(i_reset),
                     .rx(rx),
                     .i_s_tick(i_s_tick),
                     .i_s_clr(w_s_clr),
                     .i_n_clr(w_n_clr),
                     .i_n_incr(w_n_incr),
                     .i_b_shift(w_b_shift),
                     .i_p_load(w_p_load),
                     .o_s_reg(w_s_reg),
                     .o_n_reg(w_n_reg),
                     .o_b_reg(w_b_reg),
                     .o_p_reg(w_p_reg)
                   );

  // Calculo de la paridad de la trama de 9 bits (datos + paridad)
  // Si es 1 tenemos error y si es 0 esta todo bien
  assign w_error = ^{w_b_reg,w_p_reg};
  assign o_rx_done = w_rx_done_fsm & ~w_error; // Si termino y no hay error o_rx_done = 1
  assign o_parity_err = w_rx_done_fsm & w_error; // Si termino y hay error o_rx_done = 0 y o_parity_err = 1
  assign o_dout = w_b_reg;

endmodule
