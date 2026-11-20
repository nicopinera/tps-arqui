//! @brief Comparador de igualdad de los branches
//!
//! Combinacional, en EX, en paralelo con la ALU. Compara los dos operandos ya forwardeados.
//!
//! @details
//! - o_eq = (i_a == i_b). beq salta con eq y bne con !eq; esa decision (con funct3, branch y
//!   valid) la arma ex_stage, como en el datapath (bloque redirect_ex).
//! - Es un modulo aparte para que la ALU no tenga que restar para comparar: la ALU calcula el
//!   resultado de la instruccion y este bloque decide el salto al mismo tiempo.
module branch_cmp #(
    parameter NBIT = 32  //! Ancho de los operandos
) (
    input  wire [NBIT-1:0] i_a,  //! Operando A (rs1 forwardeado)
    input  wire [NBIT-1:0] i_b,  //! Operando B (rs2 forwardeado)
    output wire            o_eq  //! 1 si i_a == i_b
);

    assign o_eq = (i_a == i_b);

endmodule
