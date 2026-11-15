//! @brief Bitmap de memoria usada de la DMEM, con contador
//!
//! Anota que palabras de la DMEM escribio el programa y lleva la cuenta de la cantidad de palabras
//! que fueron escritas. Recibe de data_mem la marca del store efectivo del nucleo (o_core_we, o_core_addr),
//! asi la condicion que escribe la memoria y la que marca el bitmap es una sola.
//!
//! @details
//! - Si i_mark, pone en 1 el bit de i_mark_addr; si ese bit pasa de 0 a 1, o_used_count se
//!   incrementa. Escribir dos veces la misma palabra cuenta una sola vez.
//! - No tiene i_enable: i_mark ya incluye i_enable y valid. Las escrituras de limpieza de la
//!   Debug Unit no llegan como marca (data_mem las excluye).
//! - i_clear_used pone bitmap y contador en 0, aunque no haya enable, y tiene prioridad sobre
//!   la marca del mismo ciclo. En el core debe conectarse a i_reset || i_clear_used.
//! - Puerto de depuracion: o_dbg_used es el bit de i_dbg_addr (combinacional).
module dmem_bitmap #(
    parameter DEPTH = 256  //! Cantidad de palabras de la DMEM (DMEM_DEPTH)
) (
    input  wire                     clock,
    input  wire                     i_clear_used,  //! Borra bitmap y contador
    // Marca desde data_mem
    input  wire                     i_mark,        //! Store efectivo del nucleo en este ciclo
    input  wire [$clog2(DEPTH)-1:0] i_mark_addr,   //! Palabra que escribe ese store
    // Puerto de la Debug Unit
    input  wire [$clog2(DEPTH)-1:0] i_dbg_addr,    //! Palabra a consultar
    output wire                     o_dbg_used,    //! 1 = el programa escribio esa palabra
    output wire [  $clog2(DEPTH):0] o_used_count   //! Palabras usadas (0 a DEPTH)
);

    localparam ADDR_BITS = $clog2(DEPTH);  // bits para direccionamiento

    reg [  DEPTH-1:0] r_used;
    reg [ADDR_BITS:0] r_used_count;

    always @(posedge clock) begin
        if (i_clear_used) begin
            r_used       <= {DEPTH{1'b0}};
            r_used_count <= {(ADDR_BITS + 1) {1'b0}};
        end else if (i_mark) begin
            // Marca como usada la palabra que se escribio
            r_used[i_mark_addr] <= 1'b1;
            // Solo cuenta la primera escritura de cada palabra
            if (!r_used[i_mark_addr]) r_used_count <= r_used_count + 1'b1;
        end
    end

    assign o_dbg_used   = r_used[i_dbg_addr];
    assign o_used_count = r_used_count;

endmodule
