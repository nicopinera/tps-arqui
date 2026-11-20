//! @brief Generador de inmediatos
//!
//! Combinacional, en ID. Segun la señal imm_type reconstruye el inmediato de 32 bits extendido en signo
//! a partir de los bits de la instruccion. Esto esta especificado en docs/interfaces/formatos.md
//! (el mismo que cumple tools/riscv_toolkit/isa/formatos.py).
//!
//! @details
//! | imm_type | Formato | Inmediato                                                     |
//! |:--------:|:-------:|:--------------------------------------------------------------|
//! | 000      | I       | {20{i[31]}}, i[31:20]                                         |
//! | 001      | S       | {20{i[31]}}, i[31:25], i[11:7]                                |
//! | 010      | B       | {19{i[31]}}, i[31], i[7], i[30:25], i[11:8], 0                |
//! | 011      | U       | i[31:12], 12'b0                                               |
//! | 100      | J       | {11{i[31]}}, i[31], i[19:12], i[20], i[30:21], 0              |
//! | otro     | -       | 0                                                             |
//!
//! @note En todos los formatos con signo, el signo es instr[31]. B y J no guardan el bit 0
//!       (los destinos son pares): se agrega un 0 al final.
module imm_gen (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] i_instr,     //! Instruccion completa (instr[6:0] no se usa: es el opcode)
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [ 2:0] i_imm_type,  //! IMM_* de control_defs.vh
    output reg  [31:0] o_imm        //! Inmediato extendido en signo
);

    `include "control_defs.vh"

    always @(*) begin
        o_imm = 32'h0000_0000;
        case (i_imm_type)
            IMM_I:   o_imm = {{20{i_instr[31]}}, i_instr[31:20]};
            IMM_S:   o_imm = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};
            IMM_B:   o_imm = {{19{i_instr[31]}}, i_instr[31], i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0};
            IMM_U:   o_imm = {i_instr[31:12], 12'b0};
            IMM_J:   o_imm = {{11{i_instr[31]}}, i_instr[31], i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0};
            default: o_imm = 32'h0000_0000;
        endcase
    end

endmodule
