module du_tx_mux #(
    parameter NBIT = 8
  )(
    input wire i_sel, // Selector para saber quien usa la UART TX

    // Primer canal
    input wire i_start_0,
    input wire [NBIT-1:0] i_data_0,
    output wire o_done_0,

    // Segundo Canal
    input wire i_start_1,
    input wire [NBIT-1:0] i_data_1,
    output wire o_done_1,

    // Salidas hacia la UART TX
    output wire o_tx_start,
    output wire [NBIT-1:0] o_tx_data,
    input wire i_tx_done
  );

  assign o_tx_start = i_sel ?i_start_1:i_start_0; //1 -> Sale el 1, 0 -> Sale canal 0
  assign o_tx_data = i_sel ? i_data_1:i_data_0;
  assign o_done_0 = i_sel ? 1'b0 : i_tx_done;
  assign o_done_1 = i_sel ? i_tx_done : 1'b0;
endmodule
