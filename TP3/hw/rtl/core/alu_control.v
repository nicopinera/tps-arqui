//! @brief Control de la ALU
//!
//! Combinacional, en EX. Traduce alu_op (de la unidad de control, viaja en ID/EX), funct3 y
//! funct7_b5 (bit 30 de la instruccion) al codigo interno alu_ctrl. Es el unico lugar que
//! traduce campos de la ISA a operaciones de la ALU. Implementa tabla_control.md, seccion 4.
//!
//! @details
//! - alu_op = 00 -> ADD (loads, stores, jalr)
//! - alu_op = 01 -> PASS_B (lui)
//! - alu_op = 10 -> R-type: funct3 + funct7_b5 (add/sub y srl/sra)
//! - alu_op = 11 -> I aritmetico: funct3; funct7_b5 SOLO con funct3 = 101 (srli/srai).
//!   En addi el bit 30 es parte del inmediato (addi x1, x0, -1024 lo tiene en 1): si se
//!   mirara, addi se ejecutaria como sub (US-201 AC2).
module alu_control (
    input  wire [1:0] i_alu_op,     //! ALU_OP_* de alu_defs.vh
    input  wire [2:0] i_funct3,     //! instr[14:12]
    input  wire       i_funct7_b5,  //! instr[30]
    output reg  [3:0] o_alu_ctrl    //! ALU_* de alu_defs.vh
);

    `include "alu_defs.vh"

    // Solo una instruccion R puede pedir SUB; en I-type el bit 30 es inmediato.
    wire w_es_sub = (i_alu_op == ALU_OP_R) && i_funct7_b5;

    always @(*) begin
        o_alu_ctrl = ALU_ADD;
        case (i_alu_op)
            ALU_OP_ADD: o_alu_ctrl = ALU_ADD;
            ALU_OP_PASS_B: o_alu_ctrl = ALU_PASS_B;
            ALU_OP_R, ALU_OP_I:
            case (i_funct3)
                F3_ADD_SUB: o_alu_ctrl = w_es_sub ? ALU_SUB : ALU_ADD;
                F3_SLL:     o_alu_ctrl = ALU_SLL;
                F3_SLT:     o_alu_ctrl = ALU_SLT;
                F3_SLTU:    o_alu_ctrl = ALU_SLTU;
                F3_XOR:     o_alu_ctrl = ALU_XOR;
                // srl/sra y srli/srai: en los dos formatos el bit 30 elige el tipo de desplazamiento.
                F3_SR:      o_alu_ctrl = i_funct7_b5 ? ALU_SRA : ALU_SRL;
                F3_OR:      o_alu_ctrl = ALU_OR;
                F3_AND:     o_alu_ctrl = ALU_AND;
                default:    o_alu_ctrl = ALU_ADD;
            endcase
            default: o_alu_ctrl = ALU_ADD;
        endcase
    end

endmodule
