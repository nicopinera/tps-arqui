//! @brief ALU de 32 bits del nucleo RV32I
//!
//! Combinacional. Evolucion de la ALU del TP1:
//! - ancho parametrizable (NBIT = 32);
//! - la operacion la elige alu_ctrl[3:0], un codigo interno que genera alu_control.v;
//! - se agregan SLL, SLT, SLTU y PASS_B; se sacan NOR y el flag de overflow
//!   (RV32I no tiene excepciones aritmeticas: todo es modulo 2^32).
//!
//! @details
//! | alu_ctrl | Operacion              | Instrucciones                         |
//! |:--------:|:-----------------------|:--------------------------------------|
//! | 0000     | a + b                  | add, addi, loads, stores, jalr        |
//! | 1000     | a - b                  | sub                                   |
//! | 0001     | a << b[4:0]            | sll, slli                             |
//! | 0010     | a < b (con signo)      | slt, slti                             |
//! | 0011     | a < b (sin signo)      | sltu, sltiu                           |
//! | 0100     | a ^ b                  | xor, xori                             |
//! | 0101     | a >> b[4:0] (logico)   | srl, srli                             |
//! | 1101     | a >>> b[4:0] (aritm.)  | sra, srai                             |
//! | 0110     | a \| b                 | or, ori                               |
//! | 0111     | a & b                  | and, andi                             |
//! | 1111     | b                      | lui                                   |
//! | otro     | 0                      | -                                     |
//!
//! @note o_zero no decide branches: beq/bne se comparan en branch_cmp (ADR-019).
module alu #(
    parameter NBIT = 32  //! Ancho de los operandos y del resultado
) (
    input  wire [NBIT-1:0] i_a,         //! Operando A (rs1 forwardeado)
    input  wire [NBIT-1:0] i_b,         //! Operando B (rs2 forwardeado o inmediato)
    input  wire [     3:0] i_alu_ctrl,  //! Operacion (ALU_* de alu_defs.vh)
    output reg  [NBIT-1:0] o_result,    //! Resultado
    output wire            o_zero       //! 1 si o_result == 0
);

    `include "alu_defs.vh"

    // Cantidad de bits del desplazamiento: 5 para NBIT = 32 (RV32I usa solo b[4:0]).
    localparam SHAMT_BITS = $clog2(NBIT);

    wire [SHAMT_BITS-1:0] w_shamt = i_b[SHAMT_BITS-1:0];

    always @(*) begin
        o_result = {NBIT{1'b0}};
        case (i_alu_ctrl)
            ALU_ADD:    o_result = i_a + i_b;
            ALU_SUB:    o_result = i_a - i_b;
            ALU_SLL:    o_result = i_a << w_shamt;
            ALU_SLT:    o_result = {{(NBIT - 1) {1'b0}}, $signed(i_a) < $signed(i_b)};
            ALU_SLTU:   o_result = {{(NBIT - 1) {1'b0}}, i_a < i_b};
            ALU_XOR:    o_result = i_a ^ i_b;
            ALU_SRL:    o_result = i_a >> w_shamt;
            // $signed hace que >>> replique el bit de signo; sin el, >>> se comporta como >>.
            ALU_SRA:    o_result = $signed(i_a) >>> w_shamt;
            ALU_OR:     o_result = i_a | i_b;
            ALU_AND:    o_result = i_a & i_b;
            ALU_PASS_B: o_result = i_b;
            default:    o_result = {NBIT{1'b0}};
        endcase
    end

    assign o_zero = (o_result == {NBIT{1'b0}});

endmodule
