//! @brief Banco de registros del nucleo RV32I
//!
//! 32 registros de 32 bits implementados con flip-flops (permiten el borrado sincronico).
//! Dos puertos de lectura combinacional para ID, uno de escritura sincronica
//! para WB y un tercer puerto de lectura para la Debug Unit.
//!
//! @details
//! - Escritura en el flanco de subida si i_we && i_enable && i_rd_addr != 0.
//! - Bypass interno: si en el mismo ciclo se escribe y se lee el mismo registro, los
//!   puertos rs1/rs2 devuelven i_wr_data. Asi ID ve el valor que WB esta escribiendo y no hace
//!   falta un stall extra.
//! - El puerto de depuracion lee el valor almacenado, sin bypass.
//! - x0 vale siempre 0 en los tres puertos.
//! - i_clear pone los 32 registros en 0, aunque i_enable = 0, y tiene prioridad sobre la
//!   escritura. En el core debe conectarse a i_reset || i_flush_all.
module reg_file #(
    parameter NBIT = 32,  //! Ancho de cada registro
    parameter NREG = 32   //! Cantidad de registros
) (
    input  wire                    clock,
    input  wire                    i_clear,     //! Borrado sincronico, independiente de i_enable
    input  wire                    i_enable,    //! Clock enable del core
    // Puerto de escritura (WB)
    input  wire                    i_we,        //! Pedido de escritura (reg_write de WB)
    input  wire [$clog2(NREG)-1:0] i_rd_addr,   //! Registro destino
    input  wire [        NBIT-1:0] i_wr_data,   //! Dato a escribir
    // Puertos de lectura (ID)
    input  wire [$clog2(NREG)-1:0] i_rs1_addr,
    input  wire [$clog2(NREG)-1:0] i_rs2_addr,
    output wire [        NBIT-1:0] o_rs1_data,
    output wire [        NBIT-1:0] o_rs2_data,
    // Puerto de depuracion (Debug Unit)
    input  wire [$clog2(NREG)-1:0] i_dbg_addr,
    output wire [        NBIT-1:0] o_dbg_data
);

    // Cantidad de bits para direccionamiento
    localparam ADDR_BITS = $clog2(NREG);
    // Direccion de X0 ('00000' para 32 regs)
    localparam [ADDR_BITS-1:0] X0 = {ADDR_BITS{1'b0}};

    reg     [NBIT-1:0] r_regs                                            [0:NREG-1];

    // La escritura efectiva: la misma condicion habilita el flanco y el bypass.
    wire               w_escribe = i_we && i_enable && (i_rd_addr != X0);

    integer            i;

    always @(posedge clock) begin
        if (i_clear) begin  // Borrado tiene mayor prioridad
            for (i = 0; i < NREG; i = i + 1) r_regs[i] <= {NBIT{1'b0}};
        end else if (w_escribe) begin
            r_regs[i_rd_addr] <= i_wr_data;  // Escribe el registro
        end
    end

    // Lectura de rs1/rs2, si es el registro x0 escribe 0; si WB escribe ese registro en este ciclo entonces hace bypass.
    assign o_rs1_data = (i_rs1_addr == X0) ? {NBIT{1'b0}} : (w_escribe && i_rd_addr == i_rs1_addr) ? i_wr_data : r_regs[i_rs1_addr];

    assign o_rs2_data = (i_rs2_addr == X0) ? {NBIT{1'b0}} : (w_escribe && i_rd_addr == i_rs2_addr) ? i_wr_data : r_regs[i_rs2_addr];

    assign o_dbg_data = (i_dbg_addr == X0) ? {NBIT{1'b0}} : r_regs[i_dbg_addr];

endmodule
