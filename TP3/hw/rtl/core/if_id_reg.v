//! @brief Latch IF/ID del pipeline
//!
//! Guarda pc, pc_plus4, instr y valid de la instruccion buscada en IF.
//!
//! @details
//! Prioridad en el flanco, de mayor a menor (riscv_core.md 3):
//! 1. i_reset: valid = 0, instr = NOP, pc = pc_plus4 = 0. Actua aunque i_enable = 0; en el core
//!    se conecta i_reset || i_flush_all.
//! 2. i_enable = 0: mantiene todo.
//! 3. i_flush (jal en ID o redireccion de EX): burbuja.
//! 4. i_stall (load-use, Hito 3): mantiene todo.
//! 5. Carga lo que viene de IF.
//!
//! Burbuja = valid = 0 e instr = NOP. Pasa con i_flush y tambien cuando IF manda i_valid = 0
//! (halt_fetch): asi un latch con valid = 0 nunca muestra una instruccion "real". pc y pc_plus4
//! se cargan igual (el snapshot muestra que direccion se descarto).
module if_id_reg (
    input  wire        clock,
    input  wire        i_reset,     //! Reset sincronico, aunque i_enable = 0
    input  wire        i_enable,    //! Clock enable del core
    input  wire        i_flush,     //! Burbuja (flush_if_id)
    input  wire        i_stall,     //! Mantiene el contenido (load-use)
    // Desde IF
    input  wire [31:0] i_pc,
    input  wire [31:0] i_pc_plus4,
    input  wire [31:0] i_instr,
    input  wire        i_valid,
    // Hacia ID
    output reg  [31:0] o_pc,
    output reg  [31:0] o_pc_plus4,
    output reg  [31:0] o_instr,
    output reg         o_valid
);

    `include "control_defs.vh"

    // La instruccion entra como burbuja si hay flush o si IF no busco nada
    wire w_burbuja = i_flush || !i_valid;

    // pc y pc_plus4
    always @(posedge clock) begin
        if (i_reset) begin
            o_pc       <= 32'h0000_0000;
            o_pc_plus4 <= 32'h0000_0000;
        end else if (i_enable && (i_flush || !i_stall)) begin
            o_pc       <= i_pc;
            o_pc_plus4 <= i_pc_plus4;
        end
    end

    // instr y valid
    always @(posedge clock) begin
        if (i_reset) begin
            o_instr <= INSTR_NOP;
            o_valid <= 1'b0;
        end else if (i_enable && (i_flush || !i_stall)) begin
            o_instr <= w_burbuja ? INSTR_NOP : i_instr;
            o_valid <= !w_burbuja;
        end
    end

endmodule
