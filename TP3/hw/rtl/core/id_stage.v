//! @brief Etapa ID del nucleo: decodificacion, inmediato, jal y deteccion de HALT
//!
//! Combinacional. Decodifica la instruccion de IF/ID y prepara todo lo que ID/EX necesita.
//!
//! @details
//! - Extrae los campos rs1, rs2, rd, funct3 y funct7_b5 de la instruccion. rs1 y rs2 van al banco
//!   de registros, que esta en riscv_core porque lo comparten ID (lectura) y WB (escritura);
//!   los datos leidos entran directo a ID/EX.
//! - Instancia control unit imm_gen (inmediato del formato que pide
//!   control_unit con imm_type).
//! - jal se resuelve aca: destino = pc + imm_J, con un sumador propio.
//!   o_redirect_jal = valid && jump, en el mismo ciclo.
//! - o_halt_detected = valid && halt: HALT o ilegal (control_unit pone halt = 1 en los dos).
//!   Activa halt_fetch en el core.
//! - Las senales de control salen sin condicionar por valid: el que las anula en una burbuja es
//!   id_ex_reg. Solo las dos salidas que actuan en este mismo ciclo (o_redirect_jal y
//!   o_halt_detected) miran i_valid.
module id_stage (
    input  wire        clock,
    input  wire        i_enable,        //! Clock enable del core (escritura del banco)
    input  wire        i_clear,         //! Borra el banco; en el core i_reset || i_flush_all
    // Desde IF/ID
    input  wire [31:0] i_pc,
    input  wire [31:0] i_instr,
    input  wire        i_valid,
    // Escritura del banco (desde WB)
    input  wire        i_wb_we,         //! valid && reg_write de WB
    input  wire [ 4:0] i_wb_rd,
    input  wire [31:0] i_wb_data,
    // Puerto de depuracion del banco (Debug Unit; sin bypass)
    input  wire [ 4:0] i_dbg_reg_addr,
    output wire [31:0] o_dbg_reg_data,
    // Operandos leidos del banco
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,
    // Campos de la instruccion (rs1 y rs2 tambien son las direcciones de lectura del banco)
    output wire [ 4:0] o_rs1,
    output wire [ 4:0] o_rs2,
    output wire [ 4:0] o_rd,
    output wire [ 2:0] o_funct3,
    output wire        o_funct7_b5,
    output wire [31:0] o_imm,           //! Inmediato ya reordenado y extendido
    // Senales de control
    output wire        o_reg_write,
    output wire        o_mem_read,
    output wire        o_mem_write,
    output wire [ 1:0] o_result_src,
    output wire        o_alu_src,
    output wire [ 1:0] o_alu_op,
    output wire        o_branch,
    output wire        o_jump,
    output wire        o_jalr,
    output wire        o_halt,
    output wire        o_illegal,
    output wire        o_uses_rs1,      //! Para la hazard unit
    output wire        o_uses_rs2,      //! Para la hazard unit
    // Redireccion de jal y deteccion de HALT (actuan en este ciclo)
    output wire        o_redirect_jal,  //! jal valido en ID
    output wire [31:0] o_jal_pc,        //! Destino del jal: pc + imm_J
    output wire        o_halt_detected  //! HALT o ilegal valido en ID
);

    wire [2:0] w_imm_type;

    // Campos de la instruccion
    assign o_rs1       = i_instr[19:15];
    assign o_rs2       = i_instr[24:20];
    assign o_rd        = i_instr[11:7];
    assign o_funct3    = i_instr[14:12];
    assign o_funct7_b5 = i_instr[30];

    reg_file u_reg_file (
        .clock     (clock),
        .i_clear   (i_clear),
        .i_enable  (i_enable),
        .i_we      (i_wb_we),
        .i_rd_addr (i_wb_rd),
        .i_wr_data (i_wb_data),
        .i_rs1_addr(o_rs1),
        .i_rs2_addr(o_rs2),
        .o_rs1_data(o_rs1_data),
        .o_rs2_data(o_rs2_data),
        .i_dbg_addr(i_dbg_reg_addr),
        .o_dbg_data(o_dbg_reg_data)
    );

    control_unit u_control_unit (
        .i_opcode    (i_instr[6:0]),
        .i_funct3    (i_instr[14:12]),
        .i_funct7    (i_instr[31:25]),
        .o_reg_write (o_reg_write),
        .o_mem_read  (o_mem_read),
        .o_mem_write (o_mem_write),
        .o_result_src(o_result_src),
        .o_alu_src   (o_alu_src),
        .o_alu_op    (o_alu_op),
        .o_branch    (o_branch),
        .o_jump      (o_jump),
        .o_jalr      (o_jalr),
        .o_imm_type  (w_imm_type),
        .o_halt      (o_halt),
        .o_illegal   (o_illegal),
        .o_uses_rs1  (o_uses_rs1),
        .o_uses_rs2  (o_uses_rs2)
    );

    imm_gen u_imm_gen (
        .i_instr   (i_instr),
        .i_imm_type(w_imm_type),
        .o_imm     (o_imm)
    );

    // jal: con un jal, imm_gen ya entrega imm_J (control_unit pide IMM_J)
    assign o_jal_pc        = i_pc + o_imm;
    assign o_redirect_jal  = i_valid && o_jump;

    assign o_halt_detected = i_valid && o_halt;

endmodule
