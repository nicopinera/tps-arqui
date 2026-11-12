//! @brief Unidad de control principal
//!
//! Combinacional, en ID. Decodifica opcode, funct3 y funct7 en las senales de control
//! especificadas docs/interfaces/tabla_control.md. Esta separada en dos bloques:
//! - legalidad (seccion 3 de la tabla): la combinacion opcode/funct3/funct7 es una de las 33;
//! - señales (seccion 2 de la tabla): que hace cada instruccion legal.
//!
//! @details
//! - HALT (opcode custom-0, cualquier otro bit): halt = 1, illegal = 0, nada mas (ADR-004).
//! - Ilegal: halt = 1 e illegal = 1, sin escrituras ni lecturas de registros (ADR-018).
//! - Las senales que la tabla marca con "-" quedan en 0 (el valor por defecto).
module control_unit (
    input  wire [6:0] i_opcode,      //! instr[6:0]
    input  wire [2:0] i_funct3,      //! instr[14:12]
    input  wire [6:0] i_funct7,      //! instr[31:25]
    output reg        o_reg_write,   //! escribe rd en WB
    output reg        o_mem_read,    //! load
    output reg        o_mem_write,   //! store
    output reg  [1:0] o_result_src,  //! RES_* de control_defs.vh
    output reg        o_alu_src,     //! 0 = rs2, 1 = inmediato
    output reg  [1:0] o_alu_op,      //! ALU_OP_* de alu_defs.vh
    output reg        o_branch,      //! beq/bne
    output reg        o_jump,        //! jal (se resuelve en ID)
    output reg        o_jalr,        //! jalr (se resuelve en EX)
    output reg  [2:0] o_imm_type,    //! IMM_* de control_defs.vh
    output reg        o_halt,        //! HALT o ilegal: detiene la busqueda
    output reg        o_illegal,     //! instruccion ilegal (siempre con o_halt = 1)
    output reg        o_uses_rs1,    //! la instruccion lee rs1 (hazard unit)
    output reg        o_uses_rs2     //! la instruccion lee rs2 (hazard unit)
);

    `include "alu_defs.vh"
    `include "control_defs.vh"

    // --- Legalidad ---
    reg r_legal;

    always @(*) begin
        r_legal = 1'b0;
        case (i_opcode)
            // R: funct7 = 0000000 siempre vale; 0100000 solo para sub y sra.
            OP_R: r_legal = (i_funct7 == F7_BASE) || (i_funct7 == F7_ALT && (i_funct3 == F3_ADD_SUB || i_funct3 == F3_SR));
            // I aritmetico: funct7 solo importa en los shifts (en el resto es inmediato).
            OP_I_ARIT:
            case (i_funct3)
                F3_SLL:  r_legal = (i_funct7 == F7_BASE);
                F3_SR:   r_legal = (i_funct7 == F7_BASE) || (i_funct7 == F7_ALT);
                default: r_legal = 1'b1;
            endcase
            OP_LOAD: r_legal = (i_funct3 == F3_LB) || (i_funct3 == F3_LH) || (i_funct3 == F3_LW) || (i_funct3 == F3_LBU) || (i_funct3 == F3_LHU);
            OP_STORE: r_legal = (i_funct3 == F3_SB) || (i_funct3 == F3_SH) || (i_funct3 == F3_SW);
            OP_BRANCH: r_legal = (i_funct3 == F3_BEQ) || (i_funct3 == F3_BNE);
            OP_JALR: r_legal = (i_funct3 == F3_JALR);
            // lui, jal y HALT: funct3/funct7 son parte del inmediato (o no se miran).
            OP_LUI, OP_JAL, OP_HALT: r_legal = 1'b1;
            default: r_legal = 1'b0;
        endcase
    end

    // --- Señales ---
    always @(*) begin
        o_reg_write  = 1'b0;
        o_mem_read   = 1'b0;
        o_mem_write  = 1'b0;
        o_result_src = RES_ALU;
        o_alu_src    = 1'b0;
        o_alu_op     = ALU_OP_ADD;
        o_branch     = 1'b0;
        o_jump       = 1'b0;
        o_jalr       = 1'b0;
        o_imm_type   = IMM_I;
        o_halt       = 1'b0;
        o_illegal    = 1'b0;
        o_uses_rs1   = 1'b0;
        o_uses_rs2   = 1'b0;

        if (!r_legal) begin
            // Ilegal: se trata como HALT, sin escribir nada (ADR-018).
            o_halt    = 1'b1;
            o_illegal = 1'b1;
        end else begin
            case (i_opcode)
                OP_R: begin
                    o_reg_write = 1'b1;
                    o_alu_op    = ALU_OP_R;
                    o_uses_rs1  = 1'b1;
                    o_uses_rs2  = 1'b1;
                end
                OP_I_ARIT: begin
                    o_reg_write = 1'b1;
                    o_alu_src   = 1'b1;
                    o_alu_op    = ALU_OP_I;
                    o_imm_type  = IMM_I;
                    o_uses_rs1  = 1'b1;
                end
                OP_LOAD: begin
                    o_reg_write  = 1'b1;
                    o_mem_read   = 1'b1;
                    o_result_src = RES_MEM;
                    o_alu_src    = 1'b1;
                    o_alu_op     = ALU_OP_ADD;
                    o_imm_type   = IMM_I;
                    o_uses_rs1   = 1'b1;
                end
                OP_JALR: begin
                    o_reg_write  = 1'b1;
                    o_result_src = RES_PC4;
                    o_alu_src    = 1'b1;
                    o_alu_op     = ALU_OP_ADD;
                    o_jalr       = 1'b1;
                    o_imm_type   = IMM_I;
                    o_uses_rs1   = 1'b1;
                end
                OP_STORE: begin
                    o_mem_write = 1'b1;
                    o_alu_src   = 1'b1;
                    o_alu_op    = ALU_OP_ADD;
                    o_imm_type  = IMM_S;
                    o_uses_rs1  = 1'b1;
                    o_uses_rs2  = 1'b1;  // store_data
                end
                OP_BRANCH: begin
                    o_branch   = 1'b1;
                    o_imm_type = IMM_B;
                    o_uses_rs1 = 1'b1;
                    o_uses_rs2 = 1'b1;
                end
                OP_LUI: begin
                    o_reg_write = 1'b1;
                    o_alu_src   = 1'b1;
                    o_alu_op    = ALU_OP_PASS_B;
                    o_imm_type  = IMM_U;
                end
                OP_JAL: begin
                    o_reg_write  = 1'b1;
                    o_result_src = RES_PC4;
                    o_jump       = 1'b1;
                    o_imm_type   = IMM_J;
                end
                OP_HALT: o_halt = 1'b1;
                default: begin
                    // No se llega: r_legal = 0 para cualquier otro opcode.
                    o_halt    = 1'b1;
                    o_illegal = 1'b1;
                end
            endcase
        end
    end

endmodule
