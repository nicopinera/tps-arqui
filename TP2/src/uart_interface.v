module uart_interface #(
    parameter NBIT = 8
  )(
    input  wire clock,
    input  wire i_reset,

    // Lado ALU (bus paralelo)
    input  wire [NBIT-1:0] i_w_data,   // dato que la ALU quiere transmitir
    input  wire i_wr,                  // pedido de escritura
    output reg  [NBIT-1:0] o_r_data,   // dato recibido, listo para leer
    input  wire i_rd,                  // pedido de lectura
    output wire o_tx_full,
    output wire o_rx_empty,

    // Lado UART
    output reg  [NBIT-1:0] o_din,      // hacia uart_tx
    output reg  o_tx_start,
    input  wire i_tx_done,

    input  wire [NBIT-1:0] i_dout,     // desde uart_rx
    input  wire i_rx_done
  );
  reg r_tx_full;
  assign o_tx_full = r_tx_full;

  always @(posedge clock)
  begin
    if (i_reset)
    begin
      r_tx_full <= 1'b0;
      o_tx_start <= 1'b0;
      o_din <= 0;
    end
    else if (i_wr && !r_tx_full)
    begin
      // La ALU pide escribir y el TX está libre: arrancamos
      o_din      <= i_w_data;
      o_tx_start <= 1'b1;
      r_tx_full  <= 1'b1;
    end
    else if (i_tx_done)
    begin
      // El TX terminó: liberamos
      o_tx_start <= 1'b0;
      r_tx_full  <= 1'b0;
    end
    else
    begin
      o_tx_start <= 1'b0;   // aseguro que tx_start solo dure 1 ciclo
    end
  end
  reg r_rx_empty;
  assign o_rx_empty = r_rx_empty;

  always @(posedge clock)
  begin
    if (i_reset)
    begin
      r_rx_empty <= 1'b1;
      o_r_data   <= 0;
    end
    else if (i_rx_done)
    begin
      o_r_data   <= i_dout;   // capturo el byte que llegó
      r_rx_empty <= 1'b0;
    end
    else if (i_rd && !r_rx_empty)
    begin
      r_rx_empty <= 1'b1;     // la ALU ya lo leyó
    end
  end

endmodule
