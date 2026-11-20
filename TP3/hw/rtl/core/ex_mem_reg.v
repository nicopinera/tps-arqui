//! @brief Latch EX/MEM del pipeline
//!
//! Guarda el resultado de EX, el dato del store, las senales de control que usan MEM y WB y los
//! metadatos de la instruccion.
//!
//! @details
//! Prioridad en el flanco, de mayor a menor:
//! 1. i_reset: todo en 0, valid = 0, instr = NOP. Actua aunque i_enable = 0; en el core se
//!    conecta i_reset || i_flush_all.
//! 2. i_enable = 0: mantiene todo.
//! 3. Carga lo que viene de EX.
//!
//! Este latch no crea burbujas: no tiene flush ni stall. Lo que ya llego a EX es del camino
//! correcto (las redirecciones se resuelven a mas tardar en EX) y sigue avanzando. Una burbuja
//! llega desde ID/EX con valid = 0 y el control ya en 0, y se copia tal cual.
//!
//! DEBUG_TRACE = 0: el campo instr vale siempre 0; no cambia nada mas.
module ex_mem_reg #(
    parameter DEBUG_TRACE = 1  //! 1 = instr lleva la instruccion; 0 = instr vale 0
) (
    input  wire        clock,
    input  wire        i_reset,       //! Reset sincronico, aunque i_enable = 0
    input  wire        i_enable,      //! Clock enable del core
    // Datos
    input  wire [31:0] i_alu_result,
    input  wire [31:0] i_store_data,  //! rs2 forwardeado
    input  wire [31:0] i_pc_plus4,
    input  wire [ 4:0] i_rd,
    input  wire [ 2:0] i_funct3,
    // Control
    input  wire        i_reg_write,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire [ 1:0] i_result_src,
    // Metadatos
    input  wire        i_halt,
    input  wire        i_illegal,
    input  wire        i_valid,
    input  wire [31:0] i_instr,
    // Salidas (mismos campos)
    output reg  [31:0] o_alu_result,
    output reg  [31:0] o_store_data,
    output reg  [31:0] o_pc_plus4,
    output reg  [ 4:0] o_rd,
    output reg  [ 2:0] o_funct3,
    output reg         o_reg_write,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg  [ 1:0] o_result_src,
    output reg         o_halt,
    output reg         o_illegal,
    output reg         o_valid,
    output reg  [31:0] o_instr
);

    `include "control_defs.vh"

    // Lo que guarda el campo instr (con DEBUG_TRACE = 0, siempre 0)
    localparam [31:0] INSTR_BURBUJA = (DEBUG_TRACE != 0) ? INSTR_NOP : 32'h0000_0000;
    wire [31:0] w_instr = (DEBUG_TRACE != 0) ? i_instr : 32'h0000_0000;

    // Datos
    always @(posedge clock) begin
        if (i_reset) begin
            o_alu_result <= 32'h0000_0000;
            o_store_data <= 32'h0000_0000;
            o_pc_plus4   <= 32'h0000_0000;
            o_rd         <= 5'd0;
            o_funct3     <= 3'd0;
        end else if (i_enable) begin
            o_alu_result <= i_alu_result;
            o_store_data <= i_store_data;
            o_pc_plus4   <= i_pc_plus4;
            o_rd         <= i_rd;
            o_funct3     <= i_funct3;
        end
    end

    // Control y fin de programa
    always @(posedge clock) begin
        if (i_reset) begin
            o_reg_write  <= 1'b0;
            o_mem_read   <= 1'b0;
            o_mem_write  <= 1'b0;
            o_result_src <= 2'b00;
            o_halt       <= 1'b0;
            o_illegal    <= 1'b0;
        end else if (i_enable) begin
            o_reg_write  <= i_reg_write;
            o_mem_read   <= i_mem_read;
            o_mem_write  <= i_mem_write;
            o_result_src <= i_result_src;
            o_halt       <= i_halt;
            o_illegal    <= i_illegal;
        end
    end

    // instr y valid
    always @(posedge clock) begin
        if (i_reset) begin
            o_instr <= INSTR_BURBUJA;
            o_valid <= 1'b0;
        end else if (i_enable) begin
            o_instr <= w_instr;
            o_valid <= i_valid;
        end
    end

endmodule
