//! @brief Unidad de forwarding
//!
//! Combinacional. Decide de donde sale cada operando de la instruccion que esta en EX: del
//! banco (lo leido en ID) o del resultado de una instruccion anterior que todavia no escribio
//! el banco.
//!
//! @details
//! - Para cada operando (rs1 -> fwd_a, rs2 -> fwd_b):
//!   - FWD_EX_MEM (10) si la instruccion en MEM escribe ese registro: es la mas reciente;
//!   - si no, FWD_MEM_WB (01) si la instruccion en WB lo escribe;
//!   - si no, FWD_ID_EX (00): el valor leido en ID ya es el correcto.
//! - Una productora cuenta solo si es valida, escribe el banco (reg_write) y su rd no es x0:
//!   x0 vale siempre 0, aunque una instruccion "lo escriba".
//! - Desde MEM/WB se reenvia el resultado final de WB (alu_result, dato de load o pc + 4); desde
//!   EX/MEM, alu_result. El load en MEM con su usuaria en EX (load-use) no se puede resolver
//!   aca: lo frena la hazard unit con un stall.
//! - No mira si la instruccion en EX usa el operando: si no lo usa (inmediato, lui), el mux
//!   alu_src o la ALU lo ignoran.
module forwarding_unit (
    // Instruccion en EX (ID/EX)
    input  wire [4:0] i_id_ex_rs1,
    input  wire [4:0] i_id_ex_rs2,
    // Instruccion en MEM (EX/MEM)
    input  wire [4:0] i_ex_mem_rd,
    input  wire       i_ex_mem_reg_write,
    input  wire       i_ex_mem_valid,
    // Instruccion en WB (MEM/WB)
    input  wire [4:0] i_mem_wb_rd,
    input  wire       i_mem_wb_reg_write,
    input  wire       i_mem_wb_valid,
    // Selectores de los muxes de forwarding de EX
    output reg  [1:0] o_fwd_a,             //! Operando A (rs1)
    output reg  [1:0] o_fwd_b              //! Operando B (rs2) y store_data
);

    `include "control_defs.vh"

    localparam [4:0] X0 = 5'd0;

    // Una instruccion puede reenviar si es valida, escribe el banco y su rd no es x0
    wire w_escribe_mem = i_ex_mem_valid && i_ex_mem_reg_write && (i_ex_mem_rd != X0);
    wire w_escribe_wb = i_mem_wb_valid && i_mem_wb_reg_write && (i_mem_wb_rd != X0);

    // Operando A
    always @(*) begin
        o_fwd_a = FWD_ID_EX;
        if (w_escribe_mem && (i_ex_mem_rd == i_id_ex_rs1)) o_fwd_a = FWD_EX_MEM;
        else if (w_escribe_wb && (i_mem_wb_rd == i_id_ex_rs1)) o_fwd_a = FWD_MEM_WB;
    end

    // Operando B
    always @(*) begin
        o_fwd_b = FWD_ID_EX;
        if (w_escribe_mem && (i_ex_mem_rd == i_id_ex_rs2)) o_fwd_b = FWD_EX_MEM;
        else if (w_escribe_wb && (i_mem_wb_rd == i_id_ex_rs2)) o_fwd_b = FWD_MEM_WB;
    end

endmodule
