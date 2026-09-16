module uart_rx #(
    parameter CANT_BIT = 8,
    parameter SB_TICK = 16
  )(
    output  reg [CANT_BIT-1:0]  dout, // Dato sampleado
    output  reg                 rx_done_tick, // pulso de 1 ciclo que avisa "termine, dout es valido"
    input   wire                clock, // Reloj
    input   wire                i_reset, // Reset
    input   wire                rx, // Linea de entrada que se samplea
    input   wire                s_tick // Salida del baudrate
  );
  localparam [2:0]
             IDLE=3'b000,
             START = 3'b001,
             DATA = 3'b010,
             PARITY = 3'B011,
             STOP = 3'b100;

  reg [2:0] state_reg, state_next;
  reg [3:0] s_reg,s_next; // contador de ticks (0 a 15)
  reg [2:0] n_reg,n_next; // contador de bits de datos (0 a 7)
  reg [CANT_BIT-1:0] b_reg,b_next; // shift register del dato
  reg p_reg,p_next; // bit de paridad

  // Bloque encargado de cargar el valor calculado en el ciclo anterior
  always @(posedge clock) begin
    if (i_reset)begin
      state_reg <= IDLE;
      s_reg <= 0;
      n_reg <= 0;
      b_reg <= 0;
      p_reg <= 0;
    end
    else begin
      state_reg <= state_next;
      s_reg <= s_next;
      n_reg <= n_next;
      b_reg <= b_next;
      p_reg <= p_next;
    end
  end

  always @(*) begin
    state_next = state_reg;
    s_next = s_reg;
    n_next = n_reg;
    b_next = b_reg;
    p_next = p_reg;
    rx_done_tick = 1'b0;

    case(state_reg)
      IDLE:begin
        if(~rx)begin // detecta el bit de bajada 
          state_next = START;
          s_next = 0;
        end
      end

      START:begin
        if(s_tick)begin
          if(s_reg==7)begin // espera 8 ticks para samplear el bit de start
            state_next = DATA;
            s_next = 0;
            n_next = 0;
          end
          else begin
            s_next = s_reg + 1;
          end
        end
      end

      DATA:begin
        if(s_tick)begin
          if(s_reg==15)begin
          s_next = 0;
          b_next = {rx,b_reg[7:1]};
          if (n_reg == (CANT_BIT-1)) begin
            state_next = PARITY;
          end
          end
        end
      end

      PARITY:begin
      end

      STOP:begin
      end
  end

endmodule
