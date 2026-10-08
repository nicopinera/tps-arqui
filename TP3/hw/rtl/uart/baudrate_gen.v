module baudrate_gen #(
    parameter COUNT_MAX = 326,
    parameter  BITS = 9
  )(
    input wire clock,
    input wire i_reset,
    output reg o_baudrate
  );

  // Como el clock es de 100 MHz, 100MHz/(19200x16) = 325.52, redondeado a 326
  reg [BITS-1:0] counter; // 9 bit -> 2**9 = 512, sobra para llegar a
  wire [BITS-1:0] next_counter;

  always@(posedge clock)
  begin
    if (i_reset) // Reset sincrono con el clock
    begin
      counter <= 0; // Pongo a cero el contador
      o_baudrate <= 0; //y la salida
    end
    else if (counter == COUNT_MAX-1)
    begin
      counter <= 0;
      o_baudrate <= 1'b1;
    end
    else
    begin
      counter <= counter + 1; // Asigno el valor del contador
      o_baudrate <= 0;
    end
  end
endmodule
