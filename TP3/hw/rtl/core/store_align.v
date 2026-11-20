//! @brief Alineacion de stores
//!
//! Combinacional, en MEM. A partir del tipo de store (funct3) y de los 2 bits bajos de la
//! direccion genera los byte enables de data_mem y ubica el dato en esos bytes.
//! Little-endian: el byte k de la palabra (bits [8k+7:8k]) es la direccion 4*palabra + k.
//!
//! @details
//! | Store | addr[1:0] | o_be  | o_data                     |
//! |:-----:|:---------:|:-----:|:---------------------------|
//! | sb    | 00        | 0001  | {4{rs2[7:0]}}              |
//! | sb    | 01        | 0010  | {4{rs2[7:0]}}              |
//! | sb    | 10        | 0100  | {4{rs2[7:0]}}              |
//! | sb    | 11        | 1000  | {4{rs2[7:0]}}              |
//! | sh    | x0        | 0011  | {2{rs2[15:0]}}             |
//! | sh    | x1        | 1100  | {2{rs2[15:0]}}             |
//! | sw    | xx        | 1111  | rs2                        |
//! | otro  | xx        | 0000  | rs2 (no escribe)           |
//!
//! @note Si el store esta desalineado (ADR-018), se ignoran los bits bajos de la direccion y se
//!       escribe en la posicion alineada: sh en una direccion impar escribe la media palabra
//!       que la contiene (sh en 5 -> 4) y sw en una direccion que no es multiplo de 4 escribe la
//!       palabra que la contiene (sw en 0x13 -> 0x10). No hay señal de error. El dato se
//!       replica en todos los bytes: los que no estan en o_be no se escriben, asi que no hace
//!       falta un desplazador.
module store_align (
    input  wire [ 2:0] i_funct3,    //! F3_SB / F3_SH / F3_SW
    input  wire [ 1:0] i_addr_low,  //! addr[1:0]: byte dentro de la palabra
    input  wire [31:0] i_data,      //! Valor de rs2
    output reg  [ 3:0] o_be,        //! Byte enables para data_mem
    output reg  [31:0] o_data       //! Dato ubicado en los bytes de o_be
);

    `include "control_defs.vh"

    localparam [3:0] BE_NINGUNO = 4'b0000;
    localparam [3:0] BE_BYTE_0 = 4'b0001;  // sb: se desplaza addr[1:0] lugares
    localparam [3:0] BE_MITAD_BAJA = 4'b0011;  // sh en addr[1] = 0
    localparam [3:0] BE_MITAD_ALTA = 4'b1100;  // sh en addr[1] = 1
    localparam [3:0] BE_TODOS = 4'b1111;

    always @(*) begin
        o_be   = BE_NINGUNO;
        o_data = i_data;
        case (i_funct3)
            F3_SB: begin
                o_be   = BE_BYTE_0 << i_addr_low;
                o_data = {4{i_data[7:0]}};
            end
            F3_SH: begin
                o_be   = i_addr_low[1] ? BE_MITAD_ALTA : BE_MITAD_BAJA;
                o_data = {2{i_data[15:0]}};
            end
            F3_SW: begin
                o_be   = BE_TODOS;
                o_data = i_data;
            end
            default: begin
                o_be   = BE_NINGUNO;
                o_data = i_data;
            end
        endcase
    end

endmodule
