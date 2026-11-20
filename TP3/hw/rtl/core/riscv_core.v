//! @brief Nucleo RV32I segmentado en 5 etapas (IF, ID, EX, MEM, WB)
//!
//! Une las etapas y los latches y expone la interfaz de docs/interfaces/riscv_core.md (el
//! contrato con la Debug Unit). Las memorias y el banco de registros estan dentro de sus
//! etapas (IMEM en IF, banco en ID, DMEM y bitmap en MEM); sus puertos de depuracion las
//! atraviesan.
//!
//! @details
//! Lo que vive en el core (no pertenece a ninguna etapa):
//! - Enable efectivo w_en = i_enable && !o_halted: con el programa terminado el nucleo no avanza
//!   aunque i_enable = 1.
//! - Reset de PC, latches y banco: i_reset || i_flush_all (actua aunque i_enable = 0). El bitmap
//!   se borra con i_reset || i_clear_used (i_flush_all no lo toca).
//! - o_halted / o_illegal: se activan cuando el HALT (o la ilegal) llega a WB y se mantienen
//!   hasta i_reset o i_flush_all.
//! - hazard_unit: todo el control de riesgos, como en el datapath. Elige el proximo PC
//!   (pc_sel) y genera StallF, StallD, FlushD, FlushE y la burbuja de ID/EX con la tabla de
//!   prioridades (redireccion de EX > ABORT > jal > load-use > HALT), y tiene el registro
//!   halt_fetch.
//! - forwarding_unit: de donde sale cada operando en EX.
//! - Buses planos de los latches con el layout de bytes del snapshot (riscv_core.md 4).
module riscv_core #(
    /* verilator lint_off UNUSEDPARAM */
    parameter NBIT           = 32,                  //! Ancho de datos (fijo en RV32I)
    /* verilator lint_on UNUSEDPARAM */
    parameter IMEM_DEPTH     = 256,                 //! Palabras de la IMEM
    parameter IMEM_ADDR_BITS = $clog2(IMEM_DEPTH),
    parameter DMEM_DEPTH     = 256,                 //! Palabras de la DMEM
    parameter DMEM_ADDR_BITS = $clog2(DMEM_DEPTH),
    parameter DEBUG_TRACE    = 1                    //! 1 = los latches llevan instr
) (
    // Control de ejecucion
    input  wire                      clock,
    input  wire                      i_reset,           //! Reset sincronico global
    input  wire                      i_enable,          //! Clock enable de todo el nucleo
    input  wire                      i_flush_all,       //! Como i_reset salvo el bitmap; sin enable
    input  wire                      i_stop_fetch,      //! ABORT: deja de buscar y drena
    output wire                      o_halted,          //! HALT o ilegal retirado (nivel)
    output wire                      o_illegal,         //! Lo retirado era una ilegal
    output wire [              31:0] o_pc,              //! Registro PC
    // Carga de la IMEM (Debug Unit)
    input  wire                      i_imem_we,
    input  wire [IMEM_ADDR_BITS-1:0] i_imem_addr,       //! Direccion de palabra
    input  wire [              31:0] i_imem_wdata,
    // DMEM: limpieza y memoria usada (Debug Unit)
    input  wire                      i_dbg_dmem_we,     //! Escribe ceros en i_dbg_dmem_addr
    input  wire [DMEM_ADDR_BITS-1:0] i_dbg_dmem_addr,
    input  wire                      i_clear_used,      //! Borra bitmap y contador
    // Lectura de depuracion
    input  wire [               4:0] i_dbg_reg_addr,
    output wire [              31:0] o_dbg_reg_data,
    input  wire [DMEM_ADDR_BITS-1:0] i_dbg_mem_addr,
    output wire [              31:0] o_dbg_mem_data,
    output wire                      o_dbg_mem_used,
    output wire [  DMEM_ADDR_BITS:0] o_dbg_used_count,
    // Senales de riesgo del ciclo
    output wire                      o_stall,
    output wire                      o_flush_if_id,
    output wire                      o_flush_id_ex,
    output wire [               1:0] o_fwd_a,
    output wire [               1:0] o_fwd_b,
    // Latches como buses planos (layout del snapshot)
    output wire [             103:0] o_if_id,
    output wire [             247:0] o_id_ex,
    output wire [             151:0] o_ex_mem,
    output wire [             143:0] o_mem_wb
);

    `include "control_defs.vh"

    // ---------------------------------------------------------------------------------------
    // Senales de cada etapa y latch
    // ---------------------------------------------------------------------------------------

    // IF
    wire [31:0] w_if_pc;
    wire [31:0] w_if_pc_plus4;
    wire [31:0] w_if_instr;
    wire        w_if_valid;

    // IF/ID
    wire [31:0] w_d_pc;
    wire [31:0] w_d_pc_plus4;
    wire [31:0] w_d_instr;
    wire        w_d_valid;

    // ID
    wire [31:0] w_id_rs1_data;
    wire [31:0] w_id_rs2_data;
    wire [ 4:0] w_id_rs1;
    wire [ 4:0] w_id_rs2;
    wire [ 4:0] w_id_rd;
    wire [ 2:0] w_id_funct3;
    wire        w_id_funct7_b5;
    wire [31:0] w_id_imm;
    wire        w_id_reg_write;
    wire        w_id_mem_read;
    wire        w_id_mem_write;
    wire [ 1:0] w_id_result_src;
    wire        w_id_alu_src;
    wire [ 1:0] w_id_alu_op;
    wire        w_id_branch;
    wire        w_id_jump;
    wire        w_id_jalr;
    wire        w_id_halt;
    wire        w_id_illegal;
    wire        w_id_uses_rs1;  // los usa la hazard unit
    wire        w_id_uses_rs2;
    wire        w_id_redirect_jal;
    wire [31:0] w_id_jal_pc;
    wire        w_id_halt_detected;

    // ID/EX
    wire [31:0] w_e_pc;
    wire [31:0] w_e_pc_plus4;
    wire [31:0] w_e_rs1_data;
    wire [31:0] w_e_rs2_data;
    wire [31:0] w_e_imm;
    wire [ 4:0] w_e_rs1;
    wire [ 4:0] w_e_rs2;
    wire [ 4:0] w_e_rd;
    wire [ 2:0] w_e_funct3;
    wire        w_e_funct7_b5;
    wire        w_e_reg_write;
    wire        w_e_mem_read;
    wire        w_e_mem_write;
    wire [ 1:0] w_e_result_src;
    wire        w_e_alu_src;
    wire [ 1:0] w_e_alu_op;
    wire        w_e_branch;
    wire        w_e_jump;
    wire        w_e_jalr;
    wire        w_e_halt;
    wire        w_e_illegal;
    wire        w_e_valid;
    wire [31:0] w_e_instr;

    // EX
    wire [31:0] w_ex_alu_result;
    wire [31:0] w_ex_store_data;
    wire        w_ex_redirect;
    wire [31:0] w_ex_redirect_pc;

    // EX/MEM
    wire [31:0] w_m_alu_result;
    wire [31:0] w_m_store_data;
    wire [31:0] w_m_pc_plus4;
    wire [ 4:0] w_m_rd;
    wire [ 2:0] w_m_funct3;
    wire        w_m_reg_write;
    wire        w_m_mem_read;
    wire        w_m_mem_write;
    wire [ 1:0] w_m_result_src;
    wire        w_m_halt;
    wire        w_m_illegal;
    wire        w_m_valid;
    wire [31:0] w_m_instr;

    // MEM
    wire [31:0] w_mem_data;

    // MEM/WB
    wire [31:0] w_w_alu_result;
    wire [31:0] w_w_mem_data;
    wire [31:0] w_w_pc_plus4;
    wire [ 4:0] w_w_rd;
    wire        w_w_reg_write;
    wire [ 1:0] w_w_result_src;
    wire        w_w_halt;
    wire        w_w_illegal;
    wire        w_w_valid;
    wire [31:0] w_w_instr;

    // WB
    wire        w_wb_we;
    wire [ 4:0] w_wb_rd;
    wire [31:0] w_wb_data;
    wire        w_wb_halt_retired;
    wire        w_wb_illegal_retired;

    // ---------------------------------------------------------------------------------------
    // Control del nucleo
    // ---------------------------------------------------------------------------------------

    reg         r_halted;
    reg         r_illegal;

    // Reset de PC, latches y banco (el bitmap tiene el suyo)
    wire        w_rst = i_reset || i_flush_all;
    // Con el programa terminado, el nucleo no avanza aunque i_enable = 1
    wire        w_en = i_enable && !r_halted;

    // Control de riesgos (hazard_unit) y forwarding (forwarding_unit)
    wire [ 1:0] w_pc_sel;
    wire        w_stall_f;
    wire        w_stall_d;
    wire        w_flush_d;
    wire        w_flush_e;
    wire        w_bubble_e;
    wire [ 1:0] w_fwd_a;
    wire [ 1:0] w_fwd_b;

    // Fin de programa: el HALT o la ilegal llego a WB
    always @(posedge clock) begin
        if (w_rst) begin
            r_halted  <= 1'b0;
            r_illegal <= 1'b0;
        end else if (w_en && w_wb_halt_retired) begin
            r_halted  <= 1'b1;
            r_illegal <= w_wb_illegal_retired;
        end
    end

    assign o_halted      = r_halted;
    assign o_illegal     = r_illegal;
    assign o_pc          = w_if_pc;

    // Senales de riesgo del ciclo: stall = load-use (StallD), flushes por redireccion
    assign o_stall       = w_stall_d;
    assign o_flush_if_id = w_flush_d;
    assign o_flush_id_ex = w_flush_e;
    assign o_fwd_a       = w_fwd_a;
    assign o_fwd_b       = w_fwd_b;

    // ---------------------------------------------------------------------------------------
    // IF
    // ---------------------------------------------------------------------------------------

    if_stage #(
        .IMEM_DEPTH(IMEM_DEPTH)
    ) u_if_stage (
        .clock       (clock),
        .i_reset     (w_rst),
        .i_enable    (w_en),
        .i_stall_f   (w_stall_f),
        .i_pc_sel    (w_pc_sel),
        .i_ex_pc     (w_ex_redirect_pc),
        .i_jal_pc    (w_id_jal_pc),
        .o_pc        (w_if_pc),
        .o_pc_plus4  (w_if_pc_plus4),
        .o_instr     (w_if_instr),
        .o_valid     (w_if_valid),
        .i_imem_we   (i_imem_we),
        .i_imem_addr (i_imem_addr),
        .i_imem_wdata(i_imem_wdata)
    );

    if_id_reg u_if_id_reg (
        .clock     (clock),
        .i_reset   (w_rst),
        .i_enable  (w_en),
        .i_flush   (w_flush_d),
        .i_stall   (w_stall_d),
        .i_pc      (w_if_pc),
        .i_pc_plus4(w_if_pc_plus4),
        .i_instr   (w_if_instr),
        .i_valid   (w_if_valid),
        .o_pc      (w_d_pc),
        .o_pc_plus4(w_d_pc_plus4),
        .o_instr   (w_d_instr),
        .o_valid   (w_d_valid)
    );

    // ---------------------------------------------------------------------------------------
    // ID
    // ---------------------------------------------------------------------------------------

    id_stage u_id_stage (
        .clock          (clock),
        .i_enable       (w_en),
        .i_clear        (w_rst),
        .i_pc           (w_d_pc),
        .i_instr        (w_d_instr),
        .i_valid        (w_d_valid),
        .i_wb_we        (w_wb_we),
        .i_wb_rd        (w_wb_rd),
        .i_wb_data      (w_wb_data),
        .i_dbg_reg_addr (i_dbg_reg_addr),
        .o_dbg_reg_data (o_dbg_reg_data),
        .o_rs1_data     (w_id_rs1_data),
        .o_rs2_data     (w_id_rs2_data),
        .o_rs1          (w_id_rs1),
        .o_rs2          (w_id_rs2),
        .o_rd           (w_id_rd),
        .o_funct3       (w_id_funct3),
        .o_funct7_b5    (w_id_funct7_b5),
        .o_imm          (w_id_imm),
        .o_reg_write    (w_id_reg_write),
        .o_mem_read     (w_id_mem_read),
        .o_mem_write    (w_id_mem_write),
        .o_result_src   (w_id_result_src),
        .o_alu_src      (w_id_alu_src),
        .o_alu_op       (w_id_alu_op),
        .o_branch       (w_id_branch),
        .o_jump         (w_id_jump),
        .o_jalr         (w_id_jalr),
        .o_halt         (w_id_halt),
        .o_illegal      (w_id_illegal),
        .o_uses_rs1     (w_id_uses_rs1),
        .o_uses_rs2     (w_id_uses_rs2),
        .o_redirect_jal (w_id_redirect_jal),
        .o_jal_pc       (w_id_jal_pc),
        .o_halt_detected(w_id_halt_detected)
    );

    id_ex_reg #(
        .DEBUG_TRACE(DEBUG_TRACE)
    ) u_id_ex_reg (
        .clock       (clock),
        .i_reset     (w_rst),
        .i_enable    (w_en),
        .i_flush     (w_flush_e),
        .i_bubble    (w_bubble_e),
        .i_pc        (w_d_pc),
        .i_pc_plus4  (w_d_pc_plus4),
        .i_rs1_data  (w_id_rs1_data),
        .i_rs2_data  (w_id_rs2_data),
        .i_imm       (w_id_imm),
        .i_rs1       (w_id_rs1),
        .i_rs2       (w_id_rs2),
        .i_rd        (w_id_rd),
        .i_funct3    (w_id_funct3),
        .i_funct7_b5 (w_id_funct7_b5),
        .i_reg_write (w_id_reg_write),
        .i_mem_read  (w_id_mem_read),
        .i_mem_write (w_id_mem_write),
        .i_result_src(w_id_result_src),
        .i_alu_src   (w_id_alu_src),
        .i_alu_op    (w_id_alu_op),
        .i_branch    (w_id_branch),
        .i_jump      (w_id_jump),
        .i_jalr      (w_id_jalr),
        .i_halt      (w_id_halt),
        .i_illegal   (w_id_illegal),
        .i_valid     (w_d_valid),
        .i_instr     (w_d_instr),
        .o_pc        (w_e_pc),
        .o_pc_plus4  (w_e_pc_plus4),
        .o_rs1_data  (w_e_rs1_data),
        .o_rs2_data  (w_e_rs2_data),
        .o_imm       (w_e_imm),
        .o_rs1       (w_e_rs1),
        .o_rs2       (w_e_rs2),
        .o_rd        (w_e_rd),
        .o_funct3    (w_e_funct3),
        .o_funct7_b5 (w_e_funct7_b5),
        .o_reg_write (w_e_reg_write),
        .o_mem_read  (w_e_mem_read),
        .o_mem_write (w_e_mem_write),
        .o_result_src(w_e_result_src),
        .o_alu_src   (w_e_alu_src),
        .o_alu_op    (w_e_alu_op),
        .o_branch    (w_e_branch),
        .o_jump      (w_e_jump),
        .o_jalr      (w_e_jalr),
        .o_halt      (w_e_halt),
        .o_illegal   (w_e_illegal),
        .o_valid     (w_e_valid),
        .o_instr     (w_e_instr)
    );

    // ---------------------------------------------------------------------------------------
    // EX
    // ---------------------------------------------------------------------------------------

    hazard_unit u_hazard_unit (
        .clock           (clock),
        .i_reset         (w_rst),
        .i_enable        (w_en),
        .i_id_ex_valid   (w_e_valid),
        .i_id_ex_mem_read(w_e_mem_read),
        .i_id_ex_rd      (w_e_rd),
        .i_if_id_rs1     (w_id_rs1),
        .i_if_id_rs2     (w_id_rs2),
        .i_uses_rs1      (w_id_uses_rs1),
        .i_uses_rs2      (w_id_uses_rs2),
        .i_redirect_ex   (w_ex_redirect),
        .i_redirect_jal  (w_id_redirect_jal),
        .i_halt_detected (w_id_halt_detected),
        .i_stop_fetch    (i_stop_fetch),
        .o_pc_sel        (w_pc_sel),
        .o_stall_f       (w_stall_f),
        .o_stall_d       (w_stall_d),
        .o_flush_d       (w_flush_d),
        .o_flush_e       (w_flush_e),
        .o_bubble_e      (w_bubble_e)
    );

    forwarding_unit u_forwarding_unit (
        .i_id_ex_rs1       (w_e_rs1),
        .i_id_ex_rs2       (w_e_rs2),
        .i_ex_mem_rd       (w_m_rd),
        .i_ex_mem_reg_write(w_m_reg_write),
        .i_ex_mem_valid    (w_m_valid),
        .i_mem_wb_rd       (w_w_rd),
        .i_mem_wb_reg_write(w_w_reg_write),
        .i_mem_wb_valid    (w_w_valid),
        .o_fwd_a           (w_fwd_a),
        .o_fwd_b           (w_fwd_b)
    );

    ex_stage u_ex_stage (
        .i_pc         (w_e_pc),
        .i_rs1_data   (w_e_rs1_data),
        .i_rs2_data   (w_e_rs2_data),
        .i_imm        (w_e_imm),
        .i_funct3     (w_e_funct3),
        .i_funct7_b5  (w_e_funct7_b5),
        .i_alu_src    (w_e_alu_src),
        .i_alu_op     (w_e_alu_op),
        .i_branch     (w_e_branch),
        .i_jalr       (w_e_jalr),
        .i_valid      (w_e_valid),
        .i_fwd_a      (w_fwd_a),
        .i_fwd_b      (w_fwd_b),
        .i_fwd_ex_mem (w_m_alu_result),
        .i_fwd_mem_wb (w_wb_data),
        .o_alu_result (w_ex_alu_result),
        .o_store_data (w_ex_store_data),
        .o_redirect   (w_ex_redirect),
        .o_redirect_pc(w_ex_redirect_pc)
    );

    ex_mem_reg #(
        .DEBUG_TRACE(DEBUG_TRACE)
    ) u_ex_mem_reg (
        .clock       (clock),
        .i_reset     (w_rst),
        .i_enable    (w_en),
        .i_alu_result(w_ex_alu_result),
        .i_store_data(w_ex_store_data),
        .i_pc_plus4  (w_e_pc_plus4),
        .i_rd        (w_e_rd),
        .i_funct3    (w_e_funct3),
        .i_reg_write (w_e_reg_write),
        .i_mem_read  (w_e_mem_read),
        .i_mem_write (w_e_mem_write),
        .i_result_src(w_e_result_src),
        .i_halt      (w_e_halt),
        .i_illegal   (w_e_illegal),
        .i_valid     (w_e_valid),
        .i_instr     (w_e_instr),
        .o_alu_result(w_m_alu_result),
        .o_store_data(w_m_store_data),
        .o_pc_plus4  (w_m_pc_plus4),
        .o_rd        (w_m_rd),
        .o_funct3    (w_m_funct3),
        .o_reg_write (w_m_reg_write),
        .o_mem_read  (w_m_mem_read),
        .o_mem_write (w_m_mem_write),
        .o_result_src(w_m_result_src),
        .o_halt      (w_m_halt),
        .o_illegal   (w_m_illegal),
        .o_valid     (w_m_valid),
        .o_instr     (w_m_instr)
    );

    // ---------------------------------------------------------------------------------------
    // MEM
    // ---------------------------------------------------------------------------------------

    mem_stage #(
        .DMEM_DEPTH(DMEM_DEPTH)
    ) u_mem_stage (
        .clock           (clock),
        .i_enable        (w_en),
        .i_alu_result    (w_m_alu_result),
        .i_store_data    (w_m_store_data),
        .i_funct3        (w_m_funct3),
        .i_mem_write     (w_m_mem_write),
        .i_valid         (w_m_valid),
        .o_mem_data      (w_mem_data),
        .i_dbg_dmem_we   (i_dbg_dmem_we),
        .i_dbg_dmem_addr (i_dbg_dmem_addr),
        .i_clear_used    (i_reset || i_clear_used),
        .i_dbg_mem_addr  (i_dbg_mem_addr),
        .o_dbg_mem_data  (o_dbg_mem_data),
        .o_dbg_mem_used  (o_dbg_mem_used),
        .o_dbg_used_count(o_dbg_used_count)
    );

    mem_wb_reg #(
        .DEBUG_TRACE(DEBUG_TRACE)
    ) u_mem_wb_reg (
        .clock       (clock),
        .i_reset     (w_rst),
        .i_enable    (w_en),
        .i_alu_result(w_m_alu_result),
        .i_mem_data  (w_mem_data),
        .i_pc_plus4  (w_m_pc_plus4),
        .i_rd        (w_m_rd),
        .i_reg_write (w_m_reg_write),
        .i_result_src(w_m_result_src),
        .i_halt      (w_m_halt),
        .i_illegal   (w_m_illegal),
        .i_valid     (w_m_valid),
        .i_instr     (w_m_instr),
        .o_alu_result(w_w_alu_result),
        .o_mem_data  (w_w_mem_data),
        .o_pc_plus4  (w_w_pc_plus4),
        .o_rd        (w_w_rd),
        .o_reg_write (w_w_reg_write),
        .o_result_src(w_w_result_src),
        .o_halt      (w_w_halt),
        .o_illegal   (w_w_illegal),
        .o_valid     (w_w_valid),
        .o_instr     (w_w_instr)
    );

    // ---------------------------------------------------------------------------------------
    // WB
    // ---------------------------------------------------------------------------------------

    wb_stage u_wb_stage (
        .i_alu_result     (w_w_alu_result),
        .i_mem_data       (w_w_mem_data),
        .i_pc_plus4       (w_w_pc_plus4),
        .i_rd             (w_w_rd),
        .i_reg_write      (w_w_reg_write),
        .i_result_src     (w_w_result_src),
        .i_halt           (w_w_halt),
        .i_illegal        (w_w_illegal),
        .i_valid          (w_w_valid),
        .o_wb_we          (w_wb_we),
        .o_wb_rd          (w_wb_rd),
        .o_wb_data        (w_wb_data),
        .o_halt_retired   (w_wb_halt_retired),
        .o_illegal_retired(w_wb_illegal_retired)
    );

    // ---------------------------------------------------------------------------------------
    // Latches como buses planos: byte k = bus[8k+7:8k], rellenos con 0
    // ---------------------------------------------------------------------------------------

    //Segun lo especificado en riscv_core.md seccion 4

    // 4.1 IF/ID (13 B)
    assign o_if_id = {7'd0, w_d_valid, w_d_instr, w_d_pc_plus4, w_d_pc};

    // 4.2 ID/EX (31 B)
    assign o_id_ex = {
        w_e_instr,  // [247:216]
        3'd0,
        w_e_result_src,
        w_e_funct7_b5,
        w_e_illegal,  // byte 26
        w_e_halt,
        w_e_jalr,
        w_e_jump,
        w_e_branch,
        w_e_alu_src,  // byte 25
        w_e_mem_write,
        w_e_mem_read,
        w_e_reg_write,
        w_e_valid,
        6'd0,
        w_e_alu_op,  // byte 24
        5'd0,
        w_e_funct3,  // byte 23
        3'd0,
        w_e_rd,  // byte 22
        3'd0,
        w_e_rs2,  // byte 21
        3'd0,
        w_e_rs1,  // byte 20
        w_e_imm,  // [159:128]
        w_e_rs2_data,  // [127:96]
        w_e_rs1_data,  // [95:64]
        w_e_pc_plus4,  // [63:32]
        w_e_pc  // [31:0]
    };

    // 4.3 EX/MEM (19 B)
    assign o_ex_mem = {
        w_m_instr,  // [151:120]
        w_m_result_src,
        w_m_mem_write,
        w_m_mem_read,  // byte 14
        w_m_reg_write,
        w_m_illegal,
        w_m_halt,
        w_m_valid,
        5'd0,
        w_m_funct3,  // byte 13
        3'd0,
        w_m_rd,  // byte 12
        w_m_pc_plus4,  // [95:64]
        w_m_store_data,  // [63:32]
        w_m_alu_result  // [31:0]
    };

    // 4.4 MEM/WB (18 B)
    assign o_mem_wb = {
        w_w_instr,  // [143:112]
        2'd0,
        w_w_result_src,
        w_w_reg_write,
        w_w_illegal,  // byte 13
        w_w_halt,
        w_w_valid,
        3'd0,
        w_w_rd,  // byte 12
        w_w_pc_plus4,  // [95:64]
        w_w_mem_data,  // [63:32]
        w_w_alu_result  // [31:0]
    };

endmodule
