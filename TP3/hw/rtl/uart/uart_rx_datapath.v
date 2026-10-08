module uart_rx_datapath #(
    parameter NBIT = 8
  )(
    input  wire clock,
    input  wire i_reset,
    input  wire rx,           // linea serie, para tomar el bit actual
    input  wire i_s_tick,     // pulso del baudrate_gen

    // Pulsos de control que vienen de la FSM
    input  wire i_s_clr, // Reiniciar el contador ticks
    input  wire i_n_clr, // Reinicia el contador de bits (n_reg)
    input  wire i_n_incr, // Aumenta el contador de bits
    input  wire i_b_shift, // Meter el bit actual en el shift reg
    input  wire i_p_load, // Guardar Paridad

    // Lo que la FSM necesita leer para decidir
    output reg  [3:0] o_s_reg, // Contador de ticks
    output reg  [2:0] o_n_reg, // Contador de bits

    // El dato final
    output reg  [NBIT-1:0] o_b_reg, // Dato final
    output reg  o_p_reg // Paridad
  );

  // Bloque encargado de actualizar el contador de ticks
  always @(posedge clock)
  begin
    if (i_reset) // LLega la señal de reset
      o_s_reg <= 0;
    else if (i_s_clr) // Llega la señal de la FSM
      o_s_reg <= 0;
    else if (i_s_tick) // Pulso del baudrate_gen
      o_s_reg <= o_s_reg + 1;
  end

  // Contador de bits de datos
  always @(posedge clock)
  begin
    if (i_reset)
      o_n_reg <= 0; // Reinicio el contador de bits
    else if (i_n_clr)
      o_n_reg <= 0; // Reinicio el contador de bits
    else if (i_n_incr)
      o_n_reg <= o_n_reg + 1; // Aumento 1
  end

  // Shift register del dato
  always @(posedge clock)
  begin
    if (i_reset)
      o_b_reg <= 0;
    else if (i_b_shift)
      o_b_reg <= {rx, o_b_reg[NBIT-1:1]};
  end

  // Bit de paridad recibido
  always @(posedge clock)
  begin
    if (i_reset)
      o_p_reg <= 0;
    else if (i_p_load)
      o_p_reg <= rx;
  end
endmodule
