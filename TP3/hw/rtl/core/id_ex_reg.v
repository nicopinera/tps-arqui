//! @brief Latch ID/EX del pipeline
//!
//! Guarda datos, señales de control y metadatos de la instruccion decodificada en ID.
//!
//! @details
//! Prioridad en el flanco, de mayor a menor:
//! 1. i_reset: todo en 0, valid = 0, instr = NOP. Actua aunque i_enable = 0; en el core se
//!    conecta i_reset || i_flush_all.
//! 2. i_enable = 0: mantiene todo.
//! 3. Burbuja (i_flush, i_bubble o i_valid = 0): valid = 0, instr = NOP y todas las senales de
//!    control en 0. Los datos (pc, operandos, inmediato, campos) se cargan igual.
//!    - i_flush: redireccion de EX; la instruccion de ID era del camino equivocado.
//!    - i_bubble: stall de load-use (Hito 3) o ABORT; la instruccion de ID no pasa a EX.
//!    - i_valid = 0: lo que hay en ID ya es una burbuja.
//! 4. Carga lo que viene de ID.
//!
//! A diferencia de IF/ID, este latch nunca mantiene por stall: con un load-use recibe una
//! burbuja (la instruccion que espera se queda en IF/ID).
//!
//! DEBUG_TRACE = 0: el campo instr vale siempre 0; no cambia nada mas.
module id_ex_reg #(
    parameter DEBUG_TRACE = 1  //! 1 = instr lleva la instruccion; 0 = instr vale 0
) (
    input  wire        clock,
    input  wire        i_reset,       //! Reset sincronico, aunque i_enable = 0
    input  wire        i_enable,      //! Clock enable del core
    input  wire        i_flush,       //! Burbuja por redireccion de EX (flush_id_ex)
    input  wire        i_bubble,      //! Burbuja por load-use o ABORT
    // Datos
    input  wire [31:0] i_pc,
    input  wire [31:0] i_pc_plus4,
    input  wire [31:0] i_rs1_data,
    input  wire [31:0] i_rs2_data,
    input  wire [31:0] i_imm,
    input  wire [ 4:0] i_rs1,
    input  wire [ 4:0] i_rs2,
    input  wire [ 4:0] i_rd,
    input  wire [ 2:0] i_funct3,
    input  wire        i_funct7_b5,
    // Control
    input  wire        i_reg_write,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire [ 1:0] i_result_src,
    input  wire        i_alu_src,
    input  wire [ 1:0] i_alu_op,
    input  wire        i_branch,
    input  wire        i_jump,
    input  wire        i_jalr,
    // Metadatos
    input  wire        i_halt,
    input  wire        i_illegal,
    input  wire        i_valid,
    input  wire [31:0] i_instr,
    // Salidas (mismos campos)
    output reg  [31:0] o_pc,
    output reg  [31:0] o_pc_plus4,
    output reg  [31:0] o_rs1_data,
    output reg  [31:0] o_rs2_data,
    output reg  [31:0] o_imm,
    output reg  [ 4:0] o_rs1,
    output reg  [ 4:0] o_rs2,
    output reg  [ 4:0] o_rd,
    output reg  [ 2:0] o_funct3,
    output reg         o_funct7_b5,
    output reg         o_reg_write,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg  [ 1:0] o_result_src,
    output reg         o_alu_src,
    output reg  [ 1:0] o_alu_op,
    output reg         o_branch,
    output reg         o_jump,
    output reg         o_jalr,
    output reg         o_halt,
    output reg         o_illegal,
    output reg         o_valid,
    output reg  [31:0] o_instr
);

    `include "control_defs.vh"

    // Lo que guarda el campo instr: la instruccion o una burbuja (con DEBUG_TRACE = 0, siempre 0)
    localparam [31:0] INSTR_BURBUJA = (DEBUG_TRACE != 0) ? INSTR_NOP : 32'h0000_0000;
    wire [31:0] w_instr = (DEBUG_TRACE != 0) ? i_instr : 32'h0000_0000;

    // La instruccion entra como burbuja si EX redirige, si hay que frenarla o si ya era burbuja
    wire        w_burbuja = i_flush || i_bubble || !i_valid;

    // Datos: se cargan igual con burbuja (para mostrarlo en el snapshot)
    always @(posedge clock) begin
        if (i_reset) begin
            o_pc        <= 32'h0000_0000;
            o_pc_plus4  <= 32'h0000_0000;
            o_rs1_data  <= 32'h0000_0000;
            o_rs2_data  <= 32'h0000_0000;
            o_imm       <= 32'h0000_0000;
            o_rs1       <= 5'd0;
            o_rs2       <= 5'd0;
            o_rd        <= 5'd0;
            o_funct3    <= 3'd0;
            o_funct7_b5 <= 1'b0;
        end else if (i_enable) begin
            o_pc        <= i_pc;
            o_pc_plus4  <= i_pc_plus4;
            o_rs1_data  <= i_rs1_data;
            o_rs2_data  <= i_rs2_data;
            o_imm       <= i_imm;
            o_rs1       <= i_rs1;
            o_rs2       <= i_rs2;
            o_rd        <= i_rd;
            o_funct3    <= i_funct3;
            o_funct7_b5 <= i_funct7_b5;
        end
    end

    // Control: en 0 si es burbuja (una burbuja nunca escribe, salta ni termina el programa)
    always @(posedge clock) begin
        if (i_reset) begin
            o_reg_write  <= 1'b0;
            o_mem_read   <= 1'b0;
            o_mem_write  <= 1'b0;
            o_result_src <= 2'b00;
            o_alu_src    <= 1'b0;
            o_alu_op     <= 2'b00;
            o_branch     <= 1'b0;
            o_jump       <= 1'b0;
            o_jalr       <= 1'b0;
            o_halt       <= 1'b0;
            o_illegal    <= 1'b0;
        end else if (i_enable) begin
            o_reg_write  <= w_burbuja ? 1'b0 : i_reg_write;
            o_mem_read   <= w_burbuja ? 1'b0 : i_mem_read;
            o_mem_write  <= w_burbuja ? 1'b0 : i_mem_write;
            o_result_src <= w_burbuja ? 2'b00 : i_result_src;
            o_alu_src    <= w_burbuja ? 1'b0 : i_alu_src;
            o_alu_op     <= w_burbuja ? 2'b00 : i_alu_op;
            o_branch     <= w_burbuja ? 1'b0 : i_branch;
            o_jump       <= w_burbuja ? 1'b0 : i_jump;
            o_jalr       <= w_burbuja ? 1'b0 : i_jalr;
            o_halt       <= w_burbuja ? 1'b0 : i_halt;
            o_illegal    <= w_burbuja ? 1'b0 : i_illegal;
        end
    end

    // instr y valid
    always @(posedge clock) begin
        if (i_reset) begin
            o_instr <= INSTR_BURBUJA;
            o_valid <= 1'b0;
        end else if (i_enable) begin
            o_instr <= w_burbuja ? INSTR_BURBUJA : w_instr;
            o_valid <= !w_burbuja;
        end
    end

endmodule
