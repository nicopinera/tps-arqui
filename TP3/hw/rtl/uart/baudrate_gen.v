module baudrate_gen #(
    parameter COUNT_MAX = 326
  )(
    input wire clock,
    input wire i_reset,
    output reg o_baudrate
  );
  // $clog2 nos da la cantidad de bit que necesitamos para representar un valor
  localparam BITS = $clog2(COUNT_MAX);

  // Para que la comparacion sea entre N bits y no N contra 32 bits
  localparam COUNT_MAX_INTERMEDIO = COUNT_MAX-1;
  localparam [BITS-1:0] COUNT_LAST  = COUNT_MAX_INTERMEDIO[BITS-1:0];

  // Siempre tenemos la cantidad de bits justa porque se calcula en funcion de COUNT_MAX
  reg [BITS-1:0] counter;

  always@(posedge clock)
  begin
    if (i_reset) // Reset sincrono con el clock
    begin
      counter <= 0; // Pongo a cero el contador
      o_baudrate <= 0; //y la salida
    end
    else if (counter == COUNT_LAST)
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
