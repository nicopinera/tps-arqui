module uart_tx #(
    parameter NBIT   = 8,
    parameter N_TICK = 16
  )(
    input  wire clock,
    input  wire i_reset,
    input  wire i_s_tick,
    input  wire i_tx_start,
    input  wire [NBIT-1:0] i_din,
    output wire o_tx,
    output wire o_tx_done
  );

  wire w_s_clr, w_n_clr, w_n_incr, w_b_load, w_b_shift, w_p_load;
  wire [3:0] w_s_reg;
  wire [2:0] w_n_reg;
  wire [NBIT-1:0] w_b_reg;
  wire w_p_reg;

  uart_tx_fsm #(
                .NBIT(NBIT),
                .N_TICK(N_TICK)
              ) fsm (
                .clock(clock),
                .i_reset(i_reset),
                .i_tx_start(i_tx_start),
                .i_s_tick(i_s_tick),
                .i_s_reg(w_s_reg),
                .i_n_reg(w_n_reg),
                .i_b0(w_b_reg[0]),
                .i_p_reg(w_p_reg),
                .o_s_clr(w_s_clr),
                .o_n_clr(w_n_clr),
                .o_n_incr(w_n_incr),
                .o_b_load(w_b_load),
                .o_b_shift(w_b_shift),
                .o_p_load(w_p_load),
                .o_tx_done(o_tx_done),
                .o_tx(o_tx)
              );

  uart_tx_datapath #(
                     .NBIT(NBIT)
                   ) datapath (
                     .clock(clock),
                     .i_reset(i_reset),
                     .i_din(i_din),
                     .i_s_tick(i_s_tick),
                     .i_s_clr(w_s_clr),
                     .i_n_clr(w_n_clr),
                     .i_n_incr(w_n_incr),
                     .i_b_load(w_b_load),
                     .i_b_shift(w_b_shift),
                     .i_p_load(w_p_load),
                     .o_s_reg(w_s_reg),
                     .o_n_reg(w_n_reg),
                     .o_b_reg(w_b_reg),
                     .o_p_reg(w_p_reg)
                   );

endmodule
