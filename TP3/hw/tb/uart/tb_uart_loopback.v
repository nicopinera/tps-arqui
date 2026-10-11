`timescale 1ns / 1ps

// Prueba de loopback de la UART del TP2: la salida del transmisor se conecta
// a la entrada del receptor y se verifica que cada byte llegue igual (US-102).
module tb_uart_loopback;
  `include "tb_utils.vh"

  localparam NBIT      = 8;
  localparam COUNT_MAX = 4;      // tick cada 4 ciclos: simulacion corta
  localparam BITS      = 3;
  localparam MAX_CICLOS = 20000; // limite por byte

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  reg  r_tx_start = 1'b0;
  reg  [NBIT-1:0] r_din = {NBIT{1'b0}};

  wire w_s_tick;
  wire w_serial;
  wire w_tx_done;
  wire w_rx_done;
  wire [NBIT-1:0] w_dout;

  integer ciclos;

  baudrate_gen #(.COUNT_MAX(COUNT_MAX), .BITS(BITS)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_tx #(.NBIT(NBIT)) u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(r_tx_start), .i_din(r_din),
    .o_tx(w_serial), .o_tx_done(w_tx_done)
  );

  uart_rx #(.NBIT(NBIT)) u_rx (
    .clock(clock), .i_reset(i_reset), .rx(w_serial), .i_s_tick(w_s_tick),
    .o_rx_done(w_rx_done), .o_dout(w_dout)
  );

  always #5 clock = ~clock;  // 100 MHz

  // Envia un byte por el TX y verifica que el RX entregue el mismo dato.
  task enviar_y_verificar;
    input [NBIT-1:0] dato;
    begin
      @(negedge clock);
      r_din      = dato;
      r_tx_start = 1'b1;
      @(negedge clock);
      r_tx_start = 1'b0;

      ciclos = 0;
      while (!w_rx_done && ciclos < MAX_CICLOS)
      begin
        @(negedge clock);
        ciclos = ciclos + 1;
      end
      if (!w_rx_done)
        tb_timeout("el receptor no entrego el dato");
      check_eq("dato recibido", {24'd0, w_dout}, {24'd0, dato});

      // Espera a que el transmisor termine el bit de stop antes del siguiente byte
      ciclos = 0;
      while (!w_tx_done && ciclos < MAX_CICLOS)
      begin
        @(negedge clock);
        ciclos = ciclos + 1;
      end
      repeat (COUNT_MAX * 16) @(negedge clock);
    end
  endtask

  initial
  begin
    tb_init;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    enviar_y_verificar(8'hA5);
    enviar_y_verificar(8'h00);
    enviar_y_verificar(8'hFF);
    enviar_y_verificar(8'h3C);

    tb_finish;
  end
endmodule
