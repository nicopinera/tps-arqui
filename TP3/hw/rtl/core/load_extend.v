//! @brief Extension de loads
//!
//! Combinacional, en MEM. De la palabra que entrega data_mem selecciona el byte o la media
//! palabra que pide el load (segun addr[1:0]) y la extiende a 32 bits con signo (lb, lh) o con
//! ceros (lbu, lhu). Little-endian: el byte k de la palabra (bits [8k+7:8k]) es la direccion
//! 4*palabra + k.
//!
//! @details
//! | Load | addr[1:0] | Toma          | Extension |
//! |:----:|:---------:|:--------------|:---------:|
//! | lb   | k         | word[8k+7:8k] | signo     |
//! | lbu  | k         | word[8k+7:8k] | ceros     |
//! | lh   | x0 / x1   | [15:0]/[31:16]| signo     |
//! | lhu  | x0 / x1   | [15:0]/[31:16]| ceros     |
//! | lw   | xx        | word          | -         |
//! | otro | xx        | 0             | -         |
//!
//! @note Si el load esta desalineado (ADR-018), se ignoran los bits bajos de la direccion y se
//!       lee la posicion alineada: lh/lhu en una direccion impar leen la media palabra que la
//!       contiene (lh en 3 -> 2) y lw en una direccion que no es multiplo de 4 lee la palabra
//!       que la contiene (lw en 0x13 -> 0x10). No hay senal de error. La salida se calcula para
//!       cualquier instruccion; solo se usa si result_src elige la memoria.
module load_extend (
    input  wire [ 2:0] i_funct3,    //! F3_LB / F3_LH / F3_LW / F3_LBU / F3_LHU
    input  wire [ 1:0] i_addr_low,  //! addr[1:0]: byte dentro de la palabra
    input  wire [31:0] i_word,      //! Palabra completa leida de data_mem
    output reg  [31:0] o_data       //! Valor a escribir en rd
);

    `include "control_defs.vh"

    reg [ 7:0] r_byte;  // byte que pide lb/lbu
    reg [15:0] r_mitad;  // media palabra que pide lh/lhu

    // Seleccion del byte y de la media palabra (little-endian)
    always @(*) begin
        r_byte = i_word[7:0];
        case (i_addr_low)
            2'd0: r_byte = i_word[7:0];
            2'd1: r_byte = i_word[15:8];
            2'd2: r_byte = i_word[23:16];
            2'd3: r_byte = i_word[31:24];
            default: r_byte = i_word[7:0];
        endcase
        r_mitad = i_addr_low[1] ? i_word[31:16] : i_word[15:0];
    end

    // Extension segun el tipo de load
    always @(*) begin
        o_data = 32'h0000_0000;
        case (i_funct3)
            F3_LB:   o_data = {{24{r_byte[7]}}, r_byte};
            F3_LBU:  o_data = {24'h00_0000, r_byte};
            F3_LH:   o_data = {{16{r_mitad[15]}}, r_mitad};
            F3_LHU:  o_data = {16'h0000, r_mitad};
            F3_LW:   o_data = i_word;
            default: o_data = 32'h0000_0000;
        endcase
    end

endmodule
