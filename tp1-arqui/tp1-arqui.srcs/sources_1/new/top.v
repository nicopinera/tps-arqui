// Aca se genera la maquina de estado
module top
#(parameter MSB = 8)(
// salidas

// entradas
    input [MSB-1:0] i_A,
    input [MSB-1:0] i_B,
    input [5:0] i_opcode,
    input i_reset,
    input clock
    );
    
    always@(posedge clock) begin
        //            
    end
endmodule
