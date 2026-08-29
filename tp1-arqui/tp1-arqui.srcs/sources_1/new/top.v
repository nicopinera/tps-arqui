// Aca se genera la maquina de estado
module top
#(parameter MSB = 8)(
    // salidas
    output [MSB-1:0] o_led,     // Salida de 8 bit para leds
    output           o_zero,    // Flag de zero    
    output           o_overflow,// Flag de overflow
    
    // entradas
    input [2:0]     i_abc,      // Nos define el valor a ingresar
    input [MSB-1:0] i_datos,    // Datos (A,B,opcode)    
    input           i_reset,    // Señal de reset
    input           clock       // Señal de clock
    );
    reg signed [MSB-1:0] A,B;
    reg [5:0] opcode;
    
    always@(posedge clock) begin
        // Reset sincrono al clock
        if(i_reset)begin
            A <= {MSB{1'b0}};
            B <= {MSB{1'b0}};
            opcode <= {6{1'b0}};
        end
        else begin
            case(i_abc)
                3'b001: A<=i_datos; // Obtenemos A
                3'b010: B<=i_datos; // Obtenemos B
                3'b100: opcode<=i_datos[5:0]; // Obtenemos el opcode
                default:; // Todos mantienen su valor
            endcase
        end          
    end
    
    alu #(.MSB(MSB)) u_alu(
        .o_resultado(o_led),
        .o_zero(o_zero),
        .o_overflow(o_overflow),
        .i_a(A),
        .i_b(B),
        .i_opc(opcode)
    );
endmodule
