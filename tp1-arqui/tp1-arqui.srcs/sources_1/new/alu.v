// Solamente se encarga de obtener A - B - Opcode y generar el resultado final
module alu_modulo #(parameter MSB = 8)(
    input [MSB-1:0] i_a,
    input [MSB-1:0] i_b,
    input [5:0] i_opc,
    output reg [MSB-1:0] o_resultado
    );
    
    always@(*) begin
    case(i_opc)
        'b100000: begin 
            o_resultado = i_a + i_b;
        end // add
        'b100010: begin 
            o_resultado = i_a - i_b;
        end // sub
        'b100100: begin 
            o_resultado = i_a & i_b;
        end // and
        'b100101: begin 
            o_resultado = i_a | i_b;
        end // or
        'b100110: begin 
            o_resultado = {MSB{1'b0}};
        end // xor
        'b000011: begin 
            o_resultado = {MSB{1'b0}};
        end // sra
        'b000010: begin 
            o_resultado = {MSB{1'b0}};
        end // srl
        'b100111: begin 
            o_resultado = {MSB{1'b0}};
        end // nor
        default: o_resultado = {MSB{1'b0}};
    endcase
    end
endmodule
