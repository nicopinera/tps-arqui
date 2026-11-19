//! @brief Unidad de riesgos: deteccion de load-use
//!
//! Combinacional. Detecta el unico riesgo de datos que el forwarding no resuelve: una
//! instruccion en ID que usa el registro que carga un load que esta en EX.
//!
//! @details
//! - El dato de un load sale de la DMEM al final de MEM. Si la instruccion siguiente lo necesita
//!   en EX, todavia no existe: hay que esperar un ciclo. Despues del stall el load esta en WB y
//!   el dato llega a EX por forwarding desde MEM/WB.
//! - stall = load valido en EX && su rd != x0 && la instruccion de ID usa ese registro como rs1
//!   o rs2. uses_rs1/uses_rs2 (control_unit) evitan stalls falsos: en un tipo I, lui o jal los
//!   bits de rs1/rs2 pueden ser parte del inmediato.
//! - Con stall, el core mantiene el PC e IF/ID y mete una burbuja en ID/EX. El stall dura un
//!   ciclo solo: al ciclo siguiente en EX hay una burbuja y la condicion deja de cumplirse.
//! - Es combinacional: actua en el flanco solo si i_enable = 1, porque PC y latches tienen
//!   i_enable.
module hazard_unit (
    // Instruccion en EX (ID/EX)
    input  wire       i_id_ex_valid,
    input  wire       i_id_ex_mem_read,  //! Es un load
    input  wire [4:0] i_id_ex_rd,
    // Instruccion en ID (IF/ID, decodificada en id_stage)
    input  wire [4:0] i_if_id_rs1,
    input  wire [4:0] i_if_id_rs2,
    input  wire       i_uses_rs1,        //! La instruccion de ID lee rs1
    input  wire       i_uses_rs2,        //! La instruccion de ID lee rs2
    // Hacia el core
    output wire       o_stall            //! PC e IF/ID se mantienen; burbuja en ID/EX
);

    localparam [4:0] X0 = 5'd0;

    // Load valido en EX que escribe un registro distinto de x0
    wire w_load_en_ex = i_id_ex_valid && i_id_ex_mem_read && (i_id_ex_rd != X0);

    // La instruccion de ID necesita el registro que carga el load
    wire w_usa_rd = (i_uses_rs1 && (i_if_id_rs1 == i_id_ex_rd)) || (i_uses_rs2 && (i_if_id_rs2 == i_id_ex_rd));

    assign o_stall = w_load_en_ex && w_usa_rd;

endmodule
