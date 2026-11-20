`timescale 1ns / 1ps

// Prueba de loopback de la UART del TP2: la salida del transmisor se conecta
// a la entrada del receptor y se verifica que cada byte llegue igual (US-102).
// Ademas inyecta tramas armadas a mano para probar la validacion de paridad (US-401, AC4).
module tb_uart_loopback;
  `include "tb_utils.vh"

  localparam NBIT      = 8;
  localparam COUNT_MAX = 4;      // tick cada 4 ciclos: simulacion corta
  localparam MAX_CICLOS = 20000; // limite por byte
  localparam CICLOS_BIT = COUNT_MAX * 16;

  // Configuracion real de la placa (ADR-002): misma formula de redondeo que el top (AC2)
  localparam integer CLK_FREQ_HZ    = 100_000_000;
  localparam integer BAUD           = 19200;
  localparam integer COUNT_MAX_REAL = (CLK_FREQ_HZ + 8 * BAUD) / (16 * BAUD);

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  reg  r_tx_start = 1'b0;
  reg  [NBIT-1:0] r_din = {NBIT{1'b0}};

  // La linea del receptor sale del transmisor o del testbench (tramas con paridad erronea)
  reg  r_usar_manual = 1'b0;
  reg  r_rx_manual = 1'b1;

  wire w_s_tick;
  wire w_serial;
  wire w_rx_line = r_usar_manual ? r_rx_manual : w_serial;
  wire w_tx_done;
  wire w_rx_done;
  wire w_parity_err;
  wire [NBIT-1:0] w_dout;

  integer ciclos;
  // Los pulsos duran un ciclo: se cuentan en cada flanco para no perder ninguno
  integer n_rx_done = 0;
  integer n_parity_err = 0;

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  // Solo se usa para medir el periodo real del tick; no alimenta a la UART
  wire w_tick_real;
  baudrate_gen #(.COUNT_MAX(COUNT_MAX_REAL)) u_baud_real (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_tick_real)
  );

  uart_tx #(.NBIT(NBIT)) u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(r_tx_start), .i_din(r_din),
    .o_tx(w_serial), .o_tx_done(w_tx_done)
  );

  uart_rx #(.NBIT(NBIT)) u_rx (
    .clock(clock), .i_reset(i_reset), .rx(w_rx_line), .i_s_tick(w_s_tick),
    .o_rx_done(w_rx_done), .o_parity_err(w_parity_err), .o_dout(w_dout)
  );

  always #5 clock = ~clock;  // 100 MHz

  always @(posedge clock)
  begin
    if (w_rx_done)
      n_rx_done = n_rx_done + 1;
    if (w_parity_err)
      n_parity_err = n_parity_err + 1;
  end

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
      repeat (CICLOS_BIT) @(negedge clock);
    end
  endtask

  // Mide los ciclos entre dos ticks de u_baud_real y verifica el error de baud (AC2).
  task verificar_baud_real;
    integer periodo;
    real baud_real, error_pct;
    begin
      ciclos = 0;
      while (!w_tick_real && ciclos < MAX_CICLOS)
      begin
        @(negedge clock);
        ciclos = ciclos + 1;
      end
      if (!w_tick_real)
        tb_timeout("u_baud_real no genero ticks");

      // Avanza un ciclo para salir del tick actual y cuenta hasta el siguiente
      @(negedge clock);
      periodo = 1;
      while (!w_tick_real && periodo < MAX_CICLOS)
      begin
        @(negedge clock);
        periodo = periodo + 1;
      end

      check_eq("periodo del tick real", periodo, COUNT_MAX_REAL);

      baud_real = CLK_FREQ_HZ / (16.0 * periodo);
      error_pct = 100.0 * (baud_real - BAUD) / BAUD;
      if (error_pct < 0.0)
        error_pct = -error_pct;
      $display("  COUNT_MAX = %0d, baud real = %0.1f bps, error = %0.3f %%",
               periodo, baud_real, error_pct);
      check_eq("error de baud < 2%", error_pct < 2.0, 1);
    end
  endtask

  // Arma una trama 8E1 bit por bit con el bit de paridad que se le pase (correcto o no).
  task enviar_trama_manual;
    input [NBIT-1:0] dato;
    input paridad;
    integer i;
    begin
      @(negedge clock);
      r_usar_manual = 1'b1;

      r_rx_manual = 1'b0;                      // start
      repeat (CICLOS_BIT) @(negedge clock);
      for (i = 0; i < NBIT; i = i + 1)
      begin
        r_rx_manual = dato[i];                 // datos, LSB primero
        repeat (CICLOS_BIT) @(negedge clock);
      end
      r_rx_manual = paridad;
      repeat (CICLOS_BIT) @(negedge clock);
      r_rx_manual = 1'b1;                      // stop
      repeat (2 * CICLOS_BIT) @(negedge clock);

      r_usar_manual = 1'b0;
    end
  endtask

  // Manda una trama manual y verifica cuantos pulsos de cada salida genero.
  task verificar_trama_manual;
    input [NBIT-1:0] dato;
    input paridad;
    input integer done_esperados;
    input integer err_esperados;
    integer done_antes, err_antes;
    begin
      done_antes = n_rx_done;
      err_antes  = n_parity_err;
      enviar_trama_manual(dato, paridad);
      check_eq("pulsos de o_rx_done", n_rx_done - done_antes, done_esperados);
      check_eq("pulsos de o_parity_err", n_parity_err - err_antes, err_esperados);
      if (done_esperados > 0)
        check_eq("dato manual recibido", {24'd0, w_dout}, {24'd0, dato});
    end
  endtask

  initial
  begin
    tb_init;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    verificar_baud_real;

    enviar_y_verificar(8'hA5);
    enviar_y_verificar(8'h00);
    enviar_y_verificar(8'hFF);
    enviar_y_verificar(8'h3C);
    check_eq("sin errores de paridad en loopback", n_parity_err, 0);

    // Trama manual con paridad correcta: valida que la task arma bien la trama
    verificar_trama_manual(8'h5A, ^8'h5A, 1, 0);
    verificar_trama_manual(8'h01, ^8'h01, 1, 0);
    // Paridad invertida: el byte no se entrega y se avisa el error (AC4)
    verificar_trama_manual(8'h5A, ~^8'h5A, 0, 1);
    verificar_trama_manual(8'h01, ~^8'h01, 0, 1);
    // Despues de un error el receptor sigue funcionando
    enviar_y_verificar(8'hC3);

    tb_finish;
  end
endmodule
