module uart_rx #(
    parameter NBIT   = 8,
    parameter N_TICK = 16
  )(
    input  wire clock,
    input  wire i_reset,
    input  wire rx,
    input  wire i_s_tick,
    output wire o_rx_done,
    output wire [NBIT-1:0] o_dout
  );

  wire w_s_clr, w_n_clr, w_n_incr, w_b_shift, w_p_load;
  wire [3:0] w_s_reg;
  wire [2:0] w_n_reg;
  wire [NBIT-1:0] w_b_reg;

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
                .o_rx_done(o_rx_done)
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
                     .o_p_reg()
                   );

  assign o_dout = w_b_reg;

endmodule
