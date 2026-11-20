//! @brief Etapa IF del nucleo: registro PC, mux de proximo PC e IMEM
//!
//! Busca una instruccion por ciclo en la IMEM (lectura combinacional) y carga el PC siguiente
//! que elige la hazard unit.
//!
//! @details
//! - Mux de proximo PC por i_pc_sel (PC_SEL_* de control_defs.vh): pc + 4, destino del jal (ID)
//!   o destino de un branch tomado / jalr (EX). La prioridad entre ellos la resuelve la hazard
//!   unit, como en el datapath (pc_sel).
//! - i_stall_f (StallF de la hazard unit): el PC no cambia y lo que sale de la IMEM no es una
//!   instruccion para ejecutar (o_valid = 0). Lo activan un load-use, un HALT/ilegal en ID y
//!   ABORT. En el load-use IF/ID se mantiene, asi que esa burbuja no entra.
//! - El PC se actualiza con i_enable && !i_stall_f. Con i_enable = 0 nada cambia.
//! - i_reset pone el PC en 0 aunque i_enable = 0. En el core se conecta i_reset || i_flush_all.
//! - Incluye la IMEM, con su puerto de escritura para la Debug Unit (no depende de i_enable).
module if_stage #(
    parameter IMEM_DEPTH = 256,  //! Palabras de la IMEM
    parameter INIT_FILE  = ""    //! .hex a precargar en la IMEM (solo simulacion)
) (
    input  wire                          clock,
    input  wire                          i_reset,       //! PC = 0, aunque i_enable = 0
    input  wire                          i_enable,      //! Clock enable del core
    // Desde la hazard unit
    input  wire                          i_stall_f,     //! StallF: PC quieto, busqueda detenida
    input  wire [                   1:0] i_pc_sel,      //! Proximo PC (PC_SEL_*)
    // Destinos de los saltos
    input  wire [                  31:0] i_ex_pc,       //! Branch tomado o jalr (EX)
    input  wire [                  31:0] i_jal_pc,      //! jal (ID)
    // Hacia IF/ID
    output wire [                  31:0] o_pc,          //! PC actual (direccion de la instruccion buscada)
    output wire [                  31:0] o_pc_plus4,
    output wire [                  31:0] o_instr,       //! IMEM[pc], combinacional
    output wire                          o_valid,       //! 0 = burbuja (busqueda detenida)
    // Carga de la IMEM (Debug Unit)
    input  wire                          i_imem_we,
    input  wire [$clog2(IMEM_DEPTH)-1:0] i_imem_addr,   //! Direccion de palabra
    input  wire [                  31:0] i_imem_wdata
);

    `include "control_defs.vh"

    localparam [31:0] PC_RESET = 32'h0000_0000;
    localparam [31:0] PC_PASO  = 32'd4;

    reg  [31:0] r_pc;
    reg  [31:0] r_pc_next;

    wire [31:0] w_pc_plus4 = r_pc + PC_PASO;

    // El PC avanza con enable si la hazard unit no lo frena
    wire        w_pc_we = i_enable && !i_stall_f;

    // Mux de proximo PC
    always @(*) begin
        r_pc_next = w_pc_plus4;
        case (i_pc_sel)
            PC_SEL_EX:  r_pc_next = i_ex_pc;
            PC_SEL_JAL: r_pc_next = i_jal_pc;
            default:    r_pc_next = w_pc_plus4;
        endcase
    end

    always @(posedge clock) begin
        if (i_reset) r_pc <= PC_RESET;
        else if (w_pc_we) r_pc <= r_pc_next;
    end

    instr_mem #(
        .DEPTH    (IMEM_DEPTH),
        .INIT_FILE(INIT_FILE)
    ) u_instr_mem (
        .clock  (clock),
        .i_pc   (r_pc),
        .o_instr(o_instr),
        .i_we   (i_imem_we),
        .i_addr (i_imem_addr),
        .i_wdata(i_imem_wdata)
    );

    assign o_pc       = r_pc;
    assign o_pc_plus4 = w_pc_plus4;
    assign o_valid    = !i_stall_f;

endmodule
