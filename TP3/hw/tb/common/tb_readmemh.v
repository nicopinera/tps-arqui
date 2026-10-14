`timescale 1ns / 1ps

// Prueba de la convencion para cargar programas en simulacion (US-102):
// el testbench recibe la ruta del .hex con +HEX=<ruta> y lo carga con $readmemh.
// Formato del .hex: una palabra de 32 bits en hexadecimal por linea.
//
//   make sim TB=tb_readmemh HEX=hw/tb/common/ejemplo.hex
//
// Los testbenches del nucleo (US-209 en adelante) usan este mismo esquema.
module tb_readmemh;
  `include "tb_utils.vh"

  localparam DEPTH = 256;

  reg [31:0]   mem [0:DEPTH-1];
  reg [1023:0] hex_file;
  integer i;

  initial
  begin
    tb_init;

    for (i = 0; i < DEPTH; i = i + 1)
      mem[i] = 32'h0000_000B; // relleno con HALT, como hace la Debug Unit (ADR-009)

    // Sin +HEX se usa el programa de ejemplo, para que `make sim-all` lo pueda correr
    if (!$value$plusargs("HEX=%s", hex_file))
      hex_file = "hw/tb/common/ejemplo.hex";
    $readmemh(hex_file, mem);

    check_eq("palabra 0 (addi x1,x0,5)",  mem[0], 32'h0050_0093);
    check_eq("palabra 1 (addi x2,x0,10)", mem[1], 32'h00A0_0113);
    check_eq("palabra 2 (add x3,x1,x2)",  mem[2], 32'h0020_81B3);
    check_eq("palabra 3 (HALT)",          mem[3], 32'h0000_000B);
    check_eq("palabra 4 (relleno)",       mem[4], 32'h0000_000B);

    tb_finish;
  end
endmodule
