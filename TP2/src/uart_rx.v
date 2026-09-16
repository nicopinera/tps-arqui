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
  localparam [1:0]
             IDLE=2'b00,
             START = 2'b01,
             DATA = 2'b10,
             STOP = 2'b11;

  reg [1:0] state_reg, state_next;
  reg [3:0] s_reg,s_next; // contador de ticks (0 a 15)
  reg [2:0] n_reg,n_next; // contador de bits de datos (0 a 7)
  reg [CANT_BIT-1:0] b_reg,b_next; // shift register del dato
endmodule
