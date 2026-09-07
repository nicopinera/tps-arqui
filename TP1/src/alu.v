//! @brief Unidad Aritmético-Lógica (ALU)
//!
//! Recibe dos operandos (A y B) junto con un código de operación (opcode)
//! y genera el resultado correspondiente junto con las flags de Zero y
//! Overflow. Soporta suma, resta, operaciones lógicas bit a bit y
//! desplazamientos aritmético/lógico.
//!
//! @param MSB Ancho en bits de los operandos y del resultado (default 8)
//!
//! @details
//! ### Opcodes soportados (i_opc)
//!
//! | Opcode (bin) | Operación | Descripción                          |
//! |:-------------:|:---------:|---------------------------------------|
//! | 6'b100000      | ADD       | o_resultado = i_a + i_b               |
//! | 6'b100010      | SUB       | o_resultado = i_a - i_b               |
//! | 6'b100100      | AND       | o_resultado = i_a & i_b               |
//! | 6'b100101      | OR        | o_resultado = i_a \| i_b              |
//! | 6'b100110      | XOR       | o_resultado = i_a ^ i_b               |
//! | 6'b000011      | SRA       | o_resultado = i_a >>> i_b (aritmético)|
//! | 6'b000010      | SRL       | o_resultado = i_a >> i_b (lógico)     |
//! | 6'b100111      | NOR       | o_resultado = ~(i_a \| i_b)           |
//! | otro           | -         | o_resultado = 0                       |
//!
//! @note El flag o_overflow solo se evalúa para ADD y SUB.
//! @note El flag o_zero se activa cuando o_resultado == 0, sin importar el opcode.
module alu #(parameter MSB = 8)(
    // Salidas
    output reg      [MSB-1:0]   o_resultado , //! Resultado de la operación seleccionada
    output reg                  o_zero      , //! Flag: se activa (1) si o_resultado == 0
    output reg                  o_overflow  , //! Flag: se activa (1) si hubo overflow en ADD/SUB
    // Entradas
    input signed    [MSB-1:0]   i_a     , //! Operando A (con signo)
    input signed    [MSB-1:0]   i_b     , //! Operando B (con signo)
    input           [5:0]       i_opc     //! Código de operación (ver tabla de opcodes soportados)
  );

  always@(*)
  begin
    o_overflow = 1'b0;
    case(i_opc)
      // ADD
      6'b100000:
      begin
        o_resultado = i_a + i_b;
        // Si A y B tienen el mismo signo y el resultado tiene signo contrario, nos pasamos
        if (i_a[MSB-1] == i_b[MSB-1] && o_resultado[MSB-1] != i_a[MSB-1])
          o_overflow = 1'b1;
      end
      // SUB
      6'b100010:
      begin
        o_resultado = i_a - i_b;
        // Si A y B tienen signo contrario y el resultado tiene signo contrario a A, nos pasamos
        if (i_a[MSB-1] != i_b[MSB-1] && o_resultado[MSB-1] != i_a[MSB-1])
          o_overflow = 1'b1;
      end

      // AND
      6'b100100:
        o_resultado = i_a & i_b;

      // OR
      6'b100101:
        o_resultado = i_a | i_b;

      // XOR
      6'b100110:
        o_resultado = i_a ^ i_b;

      // SRA -> Desplazamiento aritmetico
      6'b000011:
        o_resultado = i_a >>> i_b; // A es el valor y B la cant a desplazar

      // SRL -> Desplazamiento Logico
      6'b000010:
        o_resultado = i_a >> i_b;

      // NOR
      6'b100111:
        o_resultado = ~(i_a | i_b);

      // Pone a cero el resultado -> Leds apagados
      default:
        o_resultado = {MSB{1'b0}};
    endcase

    // Verificamos si el resultado fue 0
    if(!o_resultado)
      o_zero = 1'b1;
    else
      o_zero = 1'b0;
  end
endmodule
