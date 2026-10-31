module uart_rx_fsm #(
    parameter NBIT = 8, // Cantidad de bit para leer
    parameter N_TICK = 16 // Cantidad de Ticks a contar
  )(
    // Salidas
    output reg o_s_clr, // Reinicia el contador de tick (s_reg)
    output reg o_n_clr, // Reinicia el contador de bits (n_reg)
    output reg o_n_incr, // Aumenta en 1 al contador de bits (n_reg)
    output reg o_b_shift, // Meter el bit actual en el shift reg
    output reg o_p_load, // Guardar la paridad (p_reg)
    output reg o_rx_done, // Indica que termino de recibir
    // entradas
    input wire clock,
    input wire i_reset,
    input wire i_s_tick, // Señal del baudrate
    input wire [3:0] i_s_reg, // Cantidad de pulsos contados
    input wire [2:0] i_n_reg, // Contador de cantidad de bits leidos
    input wire rx // Linea RX a leer

  );
  localparam [2:0]
             IDLE=3'b000,
             START = 3'b001,
             DATA = 3'b010,
             PARITY = 3'b011,
             STOP = 3'b100;

  reg [2:0] state_reg, state_next; // Registro de estado actual y siguiente

  // Constantes de comparacion con el ancho de los contadores del datapath
  localparam integer S_LAST_I = N_TICK - 1;
  localparam integer N_LAST_I = NBIT - 1;
  localparam [3:0] S_LAST = S_LAST_I[3:0]; // ultimo tick de un bit
  localparam [2:0] N_LAST = N_LAST_I[2:0]; // ultimo bit de datos
  localparam integer S_HALF_I = (N_TICK / 2) - 1;
  localparam [3:0] S_HALF = S_HALF_I[3:0]; // mitad del bit de start

  // Se encarga unicamente de actualizar el estado
  always@(posedge clock)
  begin
    if(i_reset)
      state_reg <= IDLE;
    else
      state_reg <= state_next;
  end

  always@(*)
  begin
    state_next   = state_reg;
    o_s_clr        = 1'b0;
    o_n_clr        = 1'b0;
    o_n_incr       = 1'b0;
    o_b_shift      = 1'b0;
    o_p_load       = 1'b0;
    o_rx_done = 1'b0;
    case(state_reg)
      IDLE:
        if(~rx)
        begin
          state_next = START;
          o_s_clr = 1'b1; // Se inicia la cuenta te ticks
        end
      START:
        if(i_s_tick && i_s_reg == S_HALF)
        begin
          state_next = DATA;
          o_s_clr      = 1'b1; // Reiniciamos el contador de ticks
          o_n_clr      = 1'b1; // Reinicia el contador de bit para una nueva trama
        end
      DATA:
        if(i_s_tick && i_s_reg == S_LAST)
        begin
          o_s_clr = 1'b1; // Reiniciar el contador
          o_b_shift = 1'b1; // Hay que meter el valor en el shiftreg
          if(i_n_reg == N_LAST) // Verificar si llegamos a los 8 bits
            state_next =PARITY; // Pasar al estado de paridad
          else
            o_n_incr = 1'b1; // Aumentar el contador de bits
        end
      PARITY:
        if (i_s_tick && i_s_reg == S_LAST)
        begin
          o_s_clr      = 1'b1; // Reiniciar el contador de ticks
          o_p_load     = 1'b1; // Indicamos que tenemos que cargar la paridad
          state_next = STOP;
        end
      STOP:
        if (i_s_tick && i_s_reg == S_LAST)
        begin
          state_next   = IDLE;
          o_rx_done = 1'b1;   // pulso de 1 ciclo: "dato listo"
        end
      default:
        state_next = IDLE; // estados no usados: volver a reposo
    endcase
  end
endmodule
