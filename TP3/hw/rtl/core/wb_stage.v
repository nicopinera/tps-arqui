//! @brief Etapa WB del nucleo: valor que se escribe en rd y fin de programa
//!
//! Combinacional. Elige el valor que vuelve al banco de registros (en id_stage) y avisa cuando
//! un HALT o una ilegal llega a WB.
//!
//! @details
//! - Mux result_src: RES_ALU (alu_result), RES_MEM (dato de memoria, loads), RES_PC4 (pc + 4,
//!   jal/jalr). 11 no lo genera control_unit y se toma como RES_ALU.
//! - o_wb_we = valid && reg_write: una burbuja nunca escribe. o_wb_rd y o_wb_data van al banco
//!   y, en el Hito 3, a la forwarding unit (o_wb_data es ResultW, la entrada FWD_MEM_WB de EX).
//! - o_halt_retired = valid && halt: el HALT o la ilegal termino de recorrer el pipeline (las
//!   instrucciones anteriores ya escribieron). o_illegal_retired = o_halt_retired && illegal.
//!   Duran lo que la instruccion este en WB; en US-210 el core las guarda en o_halted/o_illegal.
module wb_stage (
    // Desde MEM/WB
    input  wire [31:0] i_alu_result,
    input  wire [31:0] i_mem_data,
    input  wire [31:0] i_pc_plus4,
    input  wire [ 4:0] i_rd,
    input  wire        i_reg_write,
    input  wire [ 1:0] i_result_src,
    input  wire        i_halt,
    input  wire        i_illegal,
    input  wire        i_valid,
    // Escritura del banco (y forwarding)
    output wire        o_wb_we,
    output wire [ 4:0] o_wb_rd,
    output reg  [31:0] o_wb_data,
    // Fin de programa
    output wire        o_halt_retired,     //! HALT o ilegal valido en WB
    output wire        o_illegal_retired   //! Lo que se retiro era una ilegal
);

    `include "control_defs.vh"

    // Valor que vuelve a rd
    always @(*) begin
        o_wb_data = i_alu_result;
        case (i_result_src)
            RES_MEM: o_wb_data = i_mem_data;
            RES_PC4: o_wb_data = i_pc_plus4;
            default: o_wb_data = i_alu_result;
        endcase
    end

    assign o_wb_we           = i_valid && i_reg_write;
    assign o_wb_rd           = i_rd;

    assign o_halt_retired    = i_valid && i_halt;
    assign o_illegal_retired = o_halt_retired && i_illegal;

endmodule
