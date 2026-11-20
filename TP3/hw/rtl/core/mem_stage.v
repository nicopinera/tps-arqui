//! @brief Etapa MEM del nucleo: acceso a la memoria de datos
//!
//! Instancia store_align, data_mem, dmem_bitmap y load_extend, conectados como en el datapath.
//!
//! @details
//! - Store: store_align ubica rs2 (ya forwardeado en EX) en los bytes que toca la direccion y
//!   arma los byte enables; data_mem escribe si mem_write && valid && i_enable (R-EJ-6).
//! - Load: data_mem entrega la palabra completa (lectura combinacional, ADR-005) y load_extend
//!   saca el byte o la media palabra y la extiende. El dato entra directo a MEM/WB.
//! - dmem_bitmap anota las palabras escritas con la marca de data_mem (o_core_we/o_core_addr).
//! - Puertos de la Debug Unit (riscv_core.md 2.3 y 2.4): limpieza de la DMEM, borrado del
//!   bitmap y lectura de una palabra con su bit de usada. Atraviesan la etapa hasta data_mem y
//!   dmem_bitmap.
//! - La direccion es alu_result (rs1 + imm). Los bits [1:0] van a store_align/load_extend y
//!   data_mem usa [ADDR_BITS+1:2]; los bits altos se ignoran (ADR-008, ADR-018).
//! - mem_read no entra: la lectura es combinacional y siempre esta disponible (mem_readM solo
//!   sirve al snapshot).
module mem_stage #(
    parameter DMEM_DEPTH = 256  //! Palabras de la DMEM
) (
    input  wire                          clock,
    input  wire                          i_enable,          //! Clock enable del core
    // Desde EX/MEM
    input  wire [                  31:0] i_alu_result,      //! Direccion de byte (rs1 + imm)
    input  wire [                  31:0] i_store_data,      //! rs2 forwardeado
    input  wire [                   2:0] i_funct3,          //! Tipo de load/store
    input  wire                          i_mem_write,
    input  wire                          i_valid,
    // Hacia MEM/WB
    output wire [                  31:0] o_mem_data,        //! Dato leido, ya extendido
    // Debug Unit
    input  wire                          i_dbg_dmem_we,     //! Escribe ceros en i_dbg_dmem_addr
    input  wire [$clog2(DMEM_DEPTH)-1:0] i_dbg_dmem_addr,   //! Palabra a limpiar
    input  wire                          i_clear_used,      //! Borra bitmap y contador
    input  wire [$clog2(DMEM_DEPTH)-1:0] i_dbg_mem_addr,    //! Palabra a leer
    output wire [                  31:0] o_dbg_mem_data,    //! DMEM[i_dbg_mem_addr]
    output wire                          o_dbg_mem_used,    //! Bit del bitmap de esa palabra
    output wire [  $clog2(DMEM_DEPTH):0] o_dbg_used_count   //! Palabras usadas (0 a DMEM_DEPTH)
);

    localparam ADDR_BITS = $clog2(DMEM_DEPTH);

    wire [          3:0] w_be;
    wire [         31:0] w_wdata;
    wire [         31:0] w_word;
    wire                 w_core_we;
    wire [ADDR_BITS-1:0] w_core_addr;

    store_align u_store_align (
        .i_funct3  (i_funct3),
        .i_addr_low(i_alu_result[1:0]),
        .i_data    (i_store_data),
        .o_be      (w_be),
        .o_data    (w_wdata)
    );

    data_mem #(
        .DEPTH(DMEM_DEPTH)
    ) u_data_mem (
        .clock        (clock),
        .i_enable     (i_enable),
        .i_we         (i_mem_write),
        .i_valid      (i_valid),
        .i_addr       (i_alu_result),
        .i_be         (w_be),
        .i_wdata      (w_wdata),
        .o_rdata      (w_word),
        .o_core_we    (w_core_we),
        .o_core_addr  (w_core_addr),
        .i_dbg_we     (i_dbg_dmem_we),
        .i_dbg_wr_addr(i_dbg_dmem_addr),
        .i_dbg_addr   (i_dbg_mem_addr),
        .o_dbg_data   (o_dbg_mem_data)
    );

    dmem_bitmap #(
        .DEPTH(DMEM_DEPTH)
    ) u_dmem_bitmap (
        .clock       (clock),
        .i_clear_used(i_clear_used),
        .i_mark      (w_core_we),
        .i_mark_addr (w_core_addr),
        .i_dbg_addr  (i_dbg_mem_addr),
        .o_dbg_used  (o_dbg_mem_used),
        .o_used_count(o_dbg_used_count)
    );

    load_extend u_load_extend (
        .i_funct3  (i_funct3),
        .i_addr_low(i_alu_result[1:0]),
        .i_word    (w_word),
        .o_data    (o_mem_data)
    );

endmodule
