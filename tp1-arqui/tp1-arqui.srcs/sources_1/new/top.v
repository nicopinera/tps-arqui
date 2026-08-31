//! @brief Módulo top: carga de registros y conexión con la ALU
//!
//! Captura los operandos A, B y el opcode desde el bus i_datos, según lo
//! indicado por i_abc, y los mantiene en registros sincronizados con clock.
//! Estos registros se conectan directamente a una instancia de la ALU,
//! cuya salida se expone en o_led junto con las flags de zero y overflow.
//!
//! @param MSB Ancho en bits de los operandos, del resultado y de o_led (default 8)
//!
//! @details
//! ### Selección de destino (i_abc)
//!
//! | i_abc (bin) | Registro cargado | Descripción                        |
//! |:-----------:|:-----------------:|-------------------------------------|
//! | 3'b001      | A                  | Carga i_datos en el operando A      |
//! | 3'b010      | B                  | Carga i_datos en el operando B      |
//! | 3'b100      | opcode             | Carga i_datos[5:0] en el opcode     |
//! | otro        | -                  | Todos los registros mantienen su valor |
//!
//! @note El reset (i_reset) es síncrono al flanco positivo de clock y
//! pone A, B y opcode en cero.
//! @note El resultado, zero y overflow son generados por la instancia
//! interna u_alu (ver documentación del módulo alu).
module top
  #(parameter MSB = 8)(
     // salidas
     output [MSB-1:0] o_led,      //! Resultado de la ALU (para leds)
     output           o_zero,     //! Flag de zero, propagada desde la ALU
     output           o_overflow, //! Flag de overflow, propagada desde la ALU

     // entradas
     input [2:0]     i_abc,       //! Selecciona qué registro se carga (ver tabla de selección)
     input [MSB-1:0] i_datos,     //! Bus de datos de entrada (A, B u opcode según i_abc)
     input           i_reset,     //! Señal de reset síncrono
     input           clock        //! Señal de clock
   );
  reg signed [MSB-1:0] A,B;
  reg [5:0] opcode;

  always@(posedge clock)
  begin
    // Reset sincrono al clock
    if(i_reset)
    begin
      A <= {MSB{1'b0}};
      B <= {MSB{1'b0}};
      opcode <= {6{1'b0}};
    end
    else
    begin
      case(i_abc)
        3'b001:
          A<=i_datos; // Obtenemos A
        3'b010:
          B<=i_datos; // Obtenemos B
        3'b100:
          opcode<=i_datos[5:0]; // Obtenemos el opcode
        default:
          ; // Todos mantienen su valor
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
