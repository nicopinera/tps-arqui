`timescale 1ns / 100ps

// En una placa con un clk de 100MHz el periodo es 10ns
// (#n: n timescale de espera)

//! @title Testbench del TP1
//! @file tb_top.v
//! @brief Testbench del módulo `top` (registros + ALU).
//!
//! Genera un reloj de 10 ns (100 MHz), aplica un reset inicial y carga A, B
//! y el opcode a través de i_abc/i_datos, como se haría con los switches.
//! Las entradas se cambian en el flanco de bajada para que estén estables
//! cuando el top las lee en el flanco de subida. Se dejan 100 ns entre cada
//! caso para observar la salida:
//!
//! 1. Caso feliz: 20 + 22 = 42.
//! 2. Suma y resta en los extremos del rango (overflow).
//! 3. Resultado cero.
//! 4. Operaciones lógicas con todos unos y todos ceros.
//! 5. Desplazamientos máximos sobre el mínimo negativo.
//! 6. Opcode inválido: la salida debe ser 0.
//! 7. Reset con los registros cargados: la salida debe volver a 0.
module tb_top ();

    // Opcodes
    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;
    localparam AND = 6'b100100;
    localparam OR  = 6'b100101;
    localparam XOR = 6'b100110;
    localparam SRA = 6'b000011;
    localparam SRL = 6'b000010;
    localparam NOR = 6'b100111;

    // Salidas (siempre wire)
    wire signed [7:0] o_led;       //! Resultado de la ALU
    wire              o_zero;      //! Flag de zero
    wire              o_overflow;  //! Flag de overflow

    // Entradas (siempre reg)
    reg         [7:0] i_datos;     //! Switches de datos
    reg         [2:0] i_abc;       //! Selección del registro a cargar
    reg               i_reset;     //! Reset síncrono, activo en alto
    reg               clock;       //! Reloj de 10 ns de periodo

    //! Secuencia de estimulos
    initial begin
        i_datos = 8'd0;
        i_abc   = 3'b000;
        clock   = 1'b0;
        i_reset = 1'b1;

        #150;
        @(negedge clock);
        i_reset = 1'b0;

        #100;

        // Caso feliz: 20 + 22 = 42
        @(negedge clock); i_datos = 8'd20; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd22; i_abc = 3'b010;
        @(negedge clock); i_datos = ADD;   i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Maximo positivo + 1: 127 + 1 = -128 -> overflow
        @(negedge clock); i_datos = 8'd127; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd1;   i_abc = 3'b010;
        @(negedge clock); i_datos = ADD;    i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Minimo negativo + (-1): -128 + (-1) = 127 -> overflow
        @(negedge clock); i_datos = -8'sd128; i_abc = 3'b001;
        @(negedge clock); i_datos = -8'sd1;   i_abc = 3'b010;
        @(negedge clock); i_datos = ADD;      i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Opuestos: 127 + (-127) = 0 -> zero
        @(negedge clock); i_datos = 8'd127;   i_abc = 3'b001;
        @(negedge clock); i_datos = -8'sd127; i_abc = 3'b010;
        @(negedge clock); i_datos = ADD;      i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Minimo negativo - 1: -128 - 1 = 127 -> overflow
        @(negedge clock); i_datos = -8'sd128; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd1;     i_abc = 3'b010;
        @(negedge clock); i_datos = SUB;      i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Maximo positivo - (-1): 127 - (-1) = -128 -> overflow
        @(negedge clock); i_datos = 8'd127; i_abc = 3'b001;
        @(negedge clock); i_datos = -8'sd1; i_abc = 3'b010;
        @(negedge clock); i_datos = SUB;    i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // 0 - (-128) = -128 -> overflow (+128 no entra en 8 bits)
        @(negedge clock); i_datos = 8'd0;     i_abc = 3'b001;
        @(negedge clock); i_datos = -8'sd128; i_abc = 3'b010;
        @(negedge clock); i_datos = SUB;      i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Iguales: -128 - (-128) = 0 -> zero, sin overflow
        @(negedge clock); i_datos = -8'sd128; i_abc = 3'b001;
        @(negedge clock); i_datos = -8'sd128; i_abc = 3'b010;
        @(negedge clock); i_datos = SUB;      i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // AND con todos ceros: 11111111 & 00000000 = 00000000 -> zero
        @(negedge clock); i_datos = 8'hFF; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'h00; i_abc = 3'b010;
        @(negedge clock); i_datos = AND;   i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // OR complementarios: 11110000 | 00001111 = 11111111
        @(negedge clock); i_datos = 8'hF0; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'h0F; i_abc = 3'b010;
        @(negedge clock); i_datos = OR;    i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // XOR iguales: 11111111 ^ 11111111 = 00000000 -> zero
        @(negedge clock); i_datos = 8'hFF; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'hFF; i_abc = 3'b010;
        @(negedge clock); i_datos = XOR;   i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // NOR con todos ceros: ~(00000000 | 00000000) = 11111111
        @(negedge clock); i_datos = 8'h00; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'h00; i_abc = 3'b010;
        @(negedge clock); i_datos = NOR;   i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // SRA maximo: 10000000 >>> 7 = 11111111 (-128 / 128 = -1)
        @(negedge clock); i_datos = 8'b10000000; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd7;        i_abc = 3'b010;
        @(negedge clock); i_datos = SRA;         i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // SRL maximo: 10000000 >> 7 = 00000001
        @(negedge clock); i_datos = 8'b10000000; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd7;        i_abc = 3'b010;
        @(negedge clock); i_datos = SRL;         i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // SRL fuera de rango: 11111111 >> 8 = 00000000 -> zero
        @(negedge clock); i_datos = 8'hFF; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd8;  i_abc = 3'b010;
        @(negedge clock); i_datos = SRL;   i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Opcode invalido: la salida debe ser 0
        @(negedge clock); i_datos = 8'd55;      i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd66;      i_abc = 3'b010;
        @(negedge clock); i_datos = 6'b111111;  i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        // Reset con los registros cargados, la salida deberia volver a 0
        @(negedge clock); i_datos = 8'd10; i_abc = 3'b001;
        @(negedge clock); i_datos = 8'd20; i_abc = 3'b010;
        @(negedge clock); i_datos = ADD;   i_abc = 3'b100;
        @(negedge clock); i_abc = 3'b000;
        #100;

        @(negedge clock);
        i_reset = 1'b1;

        #50;

        @(negedge clock);
        i_reset = 1'b0;

        #100;
        $finish;
    end

    //! Generacion del reloj (periodo de 10 ns)
    always #5 clock = ~clock;

    //! Dispositivo bajo prueba
    top u_top (
        .clock     (clock),
        .i_reset   (i_reset),
        .i_abc     (i_abc),
        .i_datos   (i_datos),
        .o_led     (o_led),
        .o_zero    (o_zero),
        .o_overflow(o_overflow)
    );

endmodule
