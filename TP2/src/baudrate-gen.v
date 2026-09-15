module baudrate_gen(
    input wire clock,
    input wire reset,
    output reg o_baudrate
);
// Como el clock es de 100 MHz, 100MHz/(19200x16) = 325.52, redondeado a 326
    reg [8:0] counter; // 9 bit -> 2**9 = 512, sobra para llegar a 

endmodule
