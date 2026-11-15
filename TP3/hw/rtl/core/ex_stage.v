//! @brief Etapa EX del nucleo: forwarding, ALU, comparacion de branches y redireccion
//!
//! Combinacional. Ejecuta la instruccion que esta en ID/EX y decide si EX redirige el PC.
//!
//! @details
//! - Muxes de forwarding (3 entradas) para los dos operandos: valor de ID/EX (FWD_ID_EX),
//!   dato que escribe WB (FWD_MEM_WB) o alu_result de EX/MEM (FWD_EX_MEM). Hasta el Hito 3 la
//!   forwarding unit no existe y el core conecta i_fwd_a = i_fwd_b = FWD_ID_EX.
//! - Mux alu_src: el operando B de la ALU es rs2 forwardeado o el inmediato.
//! - o_store_data es rs2 forwardeado (antes del mux alu_src): un store usa el inmediato en la
//!   ALU para la direccion y rs2 como dato (PRD 3.2).
//! - Instancia alu_control, alu y branch_cmp. branch_cmp compara los operandos forwardeados,
//!   en paralelo con la ALU.
//! - Redireccion (ADR-006): o_redirect = valid && (branch tomado || jalr). Destino:
//!   - branch: pc + imm_B, con un sumador propio;
//!   - jalr: alu_result & ~1 (la ALU calcula rs1 + imm).
//!   En el core, o_redirect hace flush de IF/ID e ID/EX (2 ciclos de penalidad).
//! - jal no se mira aca: ya redirigio desde ID. Su direccion de retorno viaja como pc_plus4,
//!   que no pasa por esta etapa (ID/EX -> EX/MEM directo), igual que rd y las senales de
//!   control que usan MEM y WB.
module ex_stage (
    // Desde ID/EX
    input  wire [31:0] i_pc,
    input  wire [31:0] i_rs1_data,
    input  wire [31:0] i_rs2_data,
    input  wire [31:0] i_imm,
    input  wire [ 2:0] i_funct3,
    input  wire        i_funct7_b5,
    input  wire        i_alu_src,
    input  wire [ 1:0] i_alu_op,
    input  wire        i_branch,
    input  wire        i_jalr,
    input  wire        i_valid,
    // Forwarding
    input  wire [ 1:0] i_fwd_a,       //! Selector del operando A (FWD_*)
    input  wire [ 1:0] i_fwd_b,       //! Selector del operando B y de store_data (FWD_*)
    input  wire [31:0] i_fwd_ex_mem,  //! alu_result de EX/MEM
    input  wire [31:0] i_fwd_mem_wb,  //! Dato que escribe WB (ResultW)
    // Hacia EX/MEM
    output wire [31:0] o_alu_result,
    output wire [31:0] o_store_data,  //! rs2 forwardeado
    // Redireccion del PC (actua en este ciclo)
    output wire        o_redirect,    //! Branch tomado o jalr, con valid
    output wire [31:0] o_redirect_pc  //! Destino del salto
);

    `include "control_defs.vh"

    // jalr: el destino tiene el bit 0 en 0 (especificacion RV32I)
    localparam [31:0] JALR_MASK = ~32'h0000_0001;

    reg  [31:0] r_op_a;  // operando A forwardeado
    reg  [31:0] r_op_b;  // operando B forwardeado (antes del mux alu_src)
    wire [31:0] w_alu_b;
    wire [ 3:0] w_alu_ctrl;
    wire        w_eq;

    // Forwarding del operando A
    always @(*) begin
        r_op_a = i_rs1_data;
        case (i_fwd_a)
            FWD_MEM_WB: r_op_a = i_fwd_mem_wb;
            FWD_EX_MEM: r_op_a = i_fwd_ex_mem;
            default:    r_op_a = i_rs1_data;
        endcase
    end

    // Forwarding del operando B
    always @(*) begin
        r_op_b = i_rs2_data;
        case (i_fwd_b)
            FWD_MEM_WB: r_op_b = i_fwd_mem_wb;
            FWD_EX_MEM: r_op_b = i_fwd_ex_mem;
            default:    r_op_b = i_rs2_data;
        endcase
    end

    // alu_src: registro (R, branches) o inmediato (I, loads, stores, jalr, lui)
    assign w_alu_b      = i_alu_src ? i_imm : r_op_b;
    assign o_store_data = r_op_b;

    alu_control u_alu_control (
        .i_alu_op   (i_alu_op),
        .i_funct3   (i_funct3),
        .i_funct7_b5(i_funct7_b5),
        .o_alu_ctrl (w_alu_ctrl)
    );

    alu u_alu (
        .i_a       (r_op_a),
        .i_b       (w_alu_b),
        .i_alu_ctrl(w_alu_ctrl),
        .o_result  (o_alu_result),
        // o_zero no decide branches (eso lo hace branch_cmp): queda sin conectar
        /* verilator lint_off PINCONNECTEMPTY */
        .o_zero    ()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    branch_cmp u_branch_cmp (
        .i_a (r_op_a),
        .i_b (r_op_b),
        .o_eq(w_eq)
    );

    // beq salta si son iguales, bne si son distintos (control_unit solo deja pasar esos dos)
    wire        w_branch_taken = i_branch && ((i_funct3 == F3_BEQ) ? w_eq : !w_eq);

    // Destinos: branch con su sumador propio; jalr con el resultado de la ALU (rs1 + imm)
    wire [31:0] w_branch_target = i_pc + i_imm;
    wire [31:0] w_jalr_target = o_alu_result & JALR_MASK;

    assign o_redirect    = i_valid && (w_branch_taken || i_jalr);
    assign o_redirect_pc = i_jalr ? w_jalr_target : w_branch_target;

endmodule
