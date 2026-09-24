module uart_interface #(
    parameter NBIT     = 8,
    parameter OPC_BITS = 6
  )(
    input  wire clock,
    input  wire i_reset,

    // Hacia la ALU
    output reg  [NBIT-1:0]     o_alu_a,
    output reg  [NBIT-1:0]     o_alu_b,
    output reg  [OPC_BITS-1:0] o_alu_opc,
    input  wire [NBIT-1:0]     i_alu_resultado,

    // Desde uart_rx
    input  wire [NBIT-1:0] i_rx_dout,
    input  wire i_rx_done,

    // Hacia uart_tx
    output reg  [NBIT-1:0] o_tx_din,
    output reg  o_tx_start,
    input  wire i_tx_done
  );

  localparam [1:0]
             BYTE_A   = 2'd0,
             BYTE_B   = 2'd1,
             BYTE_OPC = 2'd2;

  reg [1:0] byte_cnt;
  reg r_tx_full;
  reg r_send_pending;

  always @(posedge clock)
  begin
    if (i_reset)
    begin
      byte_cnt       <= BYTE_A;
      o_alu_a        <= 0;
      o_alu_b        <= 0;
      o_alu_opc      <= 0;
      o_tx_din       <= 0;
      o_tx_start     <= 1'b0;
      r_tx_full      <= 1'b0;
      r_send_pending <= 1'b0;
    end
    else
    begin
      o_tx_start <= 1'b0;   // default: pulso de 1 ciclo, se apaga solo

      // Captura de bytes entrantes segun en que posicion de la secuencia estamos
      if (i_rx_done)
      begin
        case (byte_cnt)
          BYTE_A:
          begin
            o_alu_a  <= i_rx_dout;
            byte_cnt <= BYTE_B;
          end
          BYTE_B:
          begin
            o_alu_b  <= i_rx_dout;
            byte_cnt <= BYTE_OPC;
          end
          BYTE_OPC:
          begin
            o_alu_opc      <= i_rx_dout[OPC_BITS-1:0];
            byte_cnt       <= BYTE_A;
            r_send_pending <= 1'b1;   // ya tenemos los 3 bytes, avisamos
          end
        endcase
      end

      // Un ciclo despues de cargar el opcode, el resultado ya esta estable
      if (r_send_pending && !r_tx_full)
      begin
        o_tx_din       <= i_alu_resultado;
        o_tx_start     <= 1'b1;
        r_tx_full      <= 1'b1;
        r_send_pending <= 1'b0;
      end

      if (i_tx_done)
        r_tx_full <= 1'b0;
    end
  end

endmodule
