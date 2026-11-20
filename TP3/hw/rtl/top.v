module top #(
    parameter CLK_FREQ_HZ = 100_000_000, // Frecuencia de Reloj
    parameter N_TICK    = 16, // Numero de tick necesario para muestrear un bit
    parameter NBIT      = 8,
    parameter BAUD = 19200
  )(
    input wire clock,
    input wire i_reset,
    input wire rx, // Linea de RX de la placa
    output wire tx, // Linea de TX de la placa
    output wire [3:0] o_led // Led: LED0 READY, LED1 RUN, LED2 HALTED, LED3 error de paridad
  );

  // Redondeo entero de CLK / (N_TICK*BAUD): se suma la mitad del divisor antes de dividir.
  // 100e6 / (16*19200) = 325.52 -> 326 -> 19171.8 bps -> error 0.15% < 2% (ADR-002, AC2)
  localparam COUNT_MAX = (CLK_FREQ_HZ+(N_TICK/2)*BAUD)/(N_TICK*BAUD); // Cantidad de ciclos de clock para producir un tick del baudrate

  wire w_s_tick; // Salida del Baudrate (un tick cada COUNT_MAX)
  wire w_rx_done; // Señal que indica que se recibio un Dato
  wire [NBIT-1:0] w_rx_dout; // Se almacena el dato que se recibio
  wire w_parity_err; // Se almacena la señal de error de paridad

  // Sincronizador de 2 flip-flops para rx: la linea viene de la PC y es
  // asincrona al clock de la FPGA. Arranca en 1 porque la linea en reposo es alta.
  (* ASYNC_REG = "TRUE" *) reg r_rx_meta;
  (* ASYNC_REG = "TRUE" *) reg r_rx_sync;

  // Bloque de sincronizacion para metaestabilidad
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

  // Modulo de Baudrate
  baudrate_gen #(
                 .COUNT_MAX(COUNT_MAX)
               ) u_baud (
                 .clock(clock),
                 .i_reset(i_reset),
                 .o_baudrate(w_s_tick)
               );

  // Modulo de UART rx
  uart_rx #(
            .NBIT(NBIT),
            .N_TICK(N_TICK)
          ) u_rx (
            .clock(clock),
            .i_reset(i_reset),
            .rx(r_rx_sync),
            .i_s_tick(w_s_tick),
            .o_rx_done(w_rx_done),
            .o_parity_err(w_parity_err),
            .o_dout(w_rx_dout)
          );

  // Modulo de UART tx
  uart_tx #(
            .NBIT(NBIT),
            .N_TICK(N_TICK)
          ) u_tx (
            .clock(clock),
            .i_reset(i_reset),
            .i_s_tick(w_s_tick),
            .i_tx_start(w_rx_done),
            .i_din(w_rx_dout),
            .o_tx(tx),
            // El eco no espera a que termine el TX: la PC manda de a bloques (US-401, D3)
            // verilator lint_off PINCONNECTEMPTY
            .o_tx_done()
            // verilator lint_on PINCONNECTEMPTY
          );

  reg r_led_parity;               // 1 = hubo al menos un error de paridad desde el reset

  always @(posedge clock)
  begin
    if (i_reset)
      r_led_parity <= 1'b0;       // se apaga solo con el boton de reset
    else if (w_parity_err)
      r_led_parity <= 1'b1;       // se prende con el primer error y queda asi
  end

  // TODO(US-403): LED0 = READY, LED1 = RUN, LED2 = HALTED salen de la Debug Unit
  assign o_led = {r_led_parity, 3'b000};

endmodule
