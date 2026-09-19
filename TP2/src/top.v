module top #(
    parameter NBIT      = 8,
    parameter OPC_BITS  = 6,
    parameter COUNT_MAX = 326,   // 100MHz / (19200*16) ~= 326
    parameter N_TICK    = 16
  )(
    input  wire clock,
    input  wire i_reset,
    input  wire rx,
    output wire tx,

    // Opcional: exponer flags para LEDs en la Basys 3
    output wire o_zero,
    output wire o_overflow,

    // Ultimo resultado enviado por UART, para verlo en LD7..LD0
    output wire [NBIT-1:0] o_led
  );

  // Wires del baudrate_gen hacia RX/TX
  wire w_s_tick;

  // Wires del RX hacia la interfaz
  wire [NBIT-1:0] w_rx_dout;
  wire w_rx_done;

  // Wires de la interfaz hacia el TX
  wire [NBIT-1:0] w_tx_din;
  wire w_tx_start;
  wire w_tx_done;

  // El dato que se manda al TX queda registrado hasta la proxima operacion
  assign o_led = w_tx_din;

  // Wires entre interfaz y ALU
  wire [NBIT-1:0]     w_alu_a;
  wire [NBIT-1:0]     w_alu_b;
  wire [OPC_BITS-1:0] w_alu_opc;
  wire [NBIT-1:0]     w_alu_resultado;

  // Sincronizador de 2 flip-flops para rx: la linea viene de la PC y es
  // asincrona al clock de la FPGA. Arranca en 1 porque la linea en reposo es alta.
  reg r_rx_meta, r_rx_sync;

  always @(posedge clock)
  begin
    if (i_reset)
    begin
      r_rx_meta <= 1'b1;
      r_rx_sync <= 1'b1;
    end
    else
    begin
      r_rx_meta <= rx;
      r_rx_sync <= r_rx_meta;
    end
  end

  baudrate_gen #(
                 .COUNT_MAX(COUNT_MAX)
               ) u_baud (
                 .clock(clock),
                 .i_reset(i_reset),
                 .o_baudrate(w_s_tick)
               );

  uart_rx #(
            .NBIT(NBIT),
            .N_TICK(N_TICK)
          ) u_rx (
            .clock(clock),
            .i_reset(i_reset),
            .rx(r_rx_sync),
            .i_s_tick(w_s_tick),
            .o_rx_done(w_rx_done),
            .o_dout(w_rx_dout)
          );

  uart_tx #(
            .NBIT(NBIT),
            .N_TICK(N_TICK)
          ) u_tx (
            .clock(clock),
            .i_reset(i_reset),
            .i_s_tick(w_s_tick),
            .i_tx_start(w_tx_start),
            .i_din(w_tx_din),
            .o_tx(tx),
            .o_tx_done(w_tx_done)
          );

  alu #(
        .MSB(NBIT)
      ) u_alu (
        .o_resultado(w_alu_resultado),
        .o_zero(o_zero),
        .o_overflow(o_overflow),
        .i_a(w_alu_a),
        .i_b(w_alu_b),
        .i_opc(w_alu_opc)
      );

  uart_interface #(
                   .NBIT(NBIT),
                   .OPC_BITS(OPC_BITS)
                 ) u_intf (
                   .clock(clock),
                   .i_reset(i_reset),
                   .o_alu_a(w_alu_a),
                   .o_alu_b(w_alu_b),
                   .o_alu_opc(w_alu_opc),
                   .i_alu_resultado(w_alu_resultado),
                   .i_rx_dout(w_rx_dout),
                   .i_rx_done(w_rx_done),
                   .o_tx_din(w_tx_din),
                   .o_tx_start(w_tx_start),
                   .i_tx_done(w_tx_done)
                 );

endmodule
