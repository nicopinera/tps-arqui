module uart_tx_datapath #(
    parameter NBIT = 8
  )(
    input  wire clock,
    input  wire i_reset,
    input  wire [NBIT-1:0] i_din,

    input  wire i_s_tick,
    input  wire i_s_clr,
    input  wire i_n_clr,
    input  wire i_n_incr,
    input  wire i_b_load,
    input  wire i_b_shift,
    input  wire i_p_load,

    output reg  [3:0] o_s_reg,
    output reg  [2:0] o_n_reg,
    output reg  [NBIT-1:0] o_b_reg,
    output reg  o_p_reg
  );

  always @(posedge clock)
  begin
    if (i_reset)
      o_s_reg <= 0;
    else if (i_s_clr)
      o_s_reg <= 0;
    else if (i_s_tick)
      o_s_reg <= o_s_reg + 1;
  end

  always @(posedge clock)
  begin
    if (i_reset)
      o_n_reg <= 0;
    else if (i_n_clr)
      o_n_reg <= 0;
    else if (i_n_incr)
      o_n_reg <= o_n_reg + 1;
  end

  always @(posedge clock)
  begin
    if (i_reset)
      o_b_reg <= 0;
    else if (i_b_load)
      o_b_reg <= i_din;
    else if (i_b_shift)
      o_b_reg <= {1'b0, o_b_reg[NBIT-1:1]};
  end

  always @(posedge clock)
  begin
    if (i_reset)
      o_p_reg <= 0;
    else if (i_p_load)
      o_p_reg <= ^i_din;
  end

endmodule
