module uart_tx_fsm #(
    parameter NBIT   = 8,
    parameter N_TICK = 16
  )
  (
    // Salidas
    output reg o_s_clr,    // reinicia el contador de ticks
    output reg o_n_clr,    // reinicia el contador de bits
    output reg o_n_incr,   // aumenta el contador de bits
    output reg o_b_load,   // carga el dato completo (din) en el shift reg
    output reg o_b_shift,  // corre el shift reg para sacar el proximo bit
    output reg o_p_load,   // calcula y guarda la paridad
    output reg o_tx_done,  // avisa que termino de transmitir
    output reg o_tx,       // la linea serie de salida

    // Entradas
    input wire clock,
    input wire i_reset,
    input wire i_tx_start, // pedido de la interfaz: "mandá un byte"
    input wire i_s_tick,
    input wire [3:0] i_s_reg,
    input wire [2:0] i_n_reg,
    input wire i_b0,       // bit 0 actual del shift register (el que se transmite ahora)
    input wire i_p_reg     // bit de paridad ya calculado
  );
  localparam [2:0]
             IDLE   = 3'b000,
             START  = 3'b001,
             DATA   = 3'b010,
             PARITY = 3'b011,
             STOP   = 3'b100;

  reg [2:0] state_reg, state_next;
  always @(posedge clock)
    if (i_reset)
      state_reg <= IDLE;
    else
      state_reg <= state_next;

  always @(*)
  begin
    state_next = state_reg;
    o_s_clr    = 1'b0;
    o_n_clr    = 1'b0;
    o_n_incr   = 1'b0;
    o_b_load   = 1'b0;
    o_b_shift  = 1'b0;
    o_p_load   = 1'b0;
    o_tx_done  = 1'b0;
    o_tx       = 1'b1;   // default: linea en reposo (1)

    case (state_reg)
      IDLE:
        if (i_tx_start)
        begin
          state_next = START;
          o_s_clr    = 1'b1;
          o_b_load   = 1'b1;  // cargar din en el shift register
          o_p_load   = 1'b1;  // calcular paridad sobre din
        end
      START:
      begin
        o_tx = 1'b0;
        if (i_s_tick && i_s_reg == (N_TICK-1))
        begin
          state_next = DATA;
          o_s_clr    = 1'b1;
          o_n_clr    = 1'b1;
        end
      end
      DATA:
      begin
        o_tx = i_b0;
        if (i_s_tick && i_s_reg == (N_TICK-1))
        begin
          o_s_clr   = 1'b1;
          o_b_shift = 1'b1;
          if (i_n_reg == (NBIT-1))
            state_next = PARITY;
          else
            o_n_incr = 1'b1;
        end
        PARITY:
        begin
          o_tx = i_p_reg;
          if (i_s_tick && i_s_reg == (N_TICK-1))
          begin
            o_s_clr    = 1'b1;
            state_next = STOP;
          end
        end
        STOP:
        begin
          o_tx = 1'b1;
          if (i_s_tick && i_s_reg == (N_TICK-1))
          begin
            state_next = IDLE;
            o_tx_done  = 1'b1;
          end
        end
      end
    endcase
  end
endmodule
