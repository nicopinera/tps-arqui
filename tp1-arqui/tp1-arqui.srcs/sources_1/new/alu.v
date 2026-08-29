// Solamente se encarga de obtener A - B - Opcode y generar el resultado final
module alu #(parameter MSB = 8)(
    // Salidas
    output reg      [MSB-1:0]   o_resultado , // Registro de resultado
    output reg                  o_zero      , // Flag de Zero
    output reg                  o_overflow  , // Flag de Overflow
    // Entradas
    input signed    [MSB-1:0]   i_a     ,
    input signed    [MSB-1:0]   i_b     ,
    input           [5:0]       i_opc
    );
 
    always@(*) begin
    o_overflow = 1'b0;
    case(i_opc)
        // ADD
        6'b100000: begin 
            o_resultado = i_a + i_b;
            // Si A y B tienen el mismo signo y el resultado tiene signo contrario, nos pasamos
            if (i_a[MSB-1] == i_b[MSB-1] && o_resultado[MSB-1] != i_a[MSB-1])
                o_overflow = 1'b1;
        end
        // SUB
        6'b100010: begin 
            o_resultado = i_a - i_b;
            // Si A y B tienen signo contrario y el resultado tiene signo contrario a A, nos pasamos
            if (i_a[MSB-1] != i_b[MSB-1] && o_resultado[MSB-1] != i_a[MSB-1])
                o_overflow = 1'b1;
        end
        
        // AND
        6'b100100: o_resultado = i_a & i_b;
        
        // OR
        6'b100101: o_resultado = i_a | i_b;
        
        // XOR
        6'b100110: o_resultado = i_a ^ i_b;
        
        // SRA -> Desplazamiento aritmetico
        6'b000011: o_resultado = i_a >>> i_b; // A es el valor y B la cant a desplazar
        
        // SRL -> Desplazamiento Logico
        6'b000010: o_resultado = i_a >> i_b;
        
        // NOR
        6'b100111: o_resultado = ~(i_a | i_b);
        
        // Pone a cero el resultado -> Leds apagados
        default: o_resultado = {MSB{1'b0}};
    endcase
    
        // Verificamos si el resultado fue 0
        if(!o_resultado)
                o_zero = 1'b1;
            else
                o_zero = 1'b0;
    end
endmodule
