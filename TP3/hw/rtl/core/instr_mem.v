//! @brief Memoria de instrucciones (IMEM) del nucleo RV32I
//!
//! Memoria distribuida (LUTRAM) inferida, de DEPTH palabras de 32 bits (ADR-005, ADR-008).
//! Lectura combinacional para IF y un puerto de escritura sincronica para la Debug Unit.
//!
//! @details
//! - Lectura: o_instr = mem[i_pc[ADDR_BITS+1:2]] en el mismo ciclo (sin latencia). Los bits
//!   bajos del PC se ignoran (los PC son multiplos de 4) y los altos tambien: fuera de rango
//!   la memoria "da la vuelta" (ADR-008).
//! - Escritura: en el flanco de subida si i_we, por direccion de palabra. No depende de
//!   i_enable: la Debug Unit carga el programa con el nucleo congelado.
//! - Sin reset: una LUTRAM no se puede borrar en un ciclo. La Debug Unit rellena la IMEM con
//!   HALT en cada LOAD (ADR-009).
//! - INIT_FILE (opcional, para simulacion): si no esta vacio, se precarga con $readmemh.
module instr_mem #(
    parameter DEPTH     = 256,  //! Cantidad de palabras (IMEM_DEPTH)
    parameter INIT_FILE = ""    //! .hex a precargar (solo simulacion); "" = sin precarga
) (
    input  wire                     clock,
    // Puerto de lectura (IF)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [             31:0] i_pc,     //! Direccion de byte; se usan [ADDR_BITS+1:2]
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [             31:0] o_instr,  //! Instruccion en mem[pc / 4]
    // Puerto de escritura (Debug Unit)
    input  wire                     i_we,     //! Escribe i_wdata en mem[i_addr]
    input  wire [$clog2(DEPTH)-1:0] i_addr,   //! Direccion de palabra
    input  wire [             31:0] i_wdata
);

    localparam ADDR_BITS = $clog2(DEPTH);
    // Bits bajos del PC que no direccionan palabras (byte dentro de la palabra)
    localparam BYTE_OFFSET_BITS = 2;

    reg  [         31:0] r_mem                                                             [0:DEPTH-1];

    // Indice de palabra: bits [ADDR_BITS+1:2] del PC
    wire [ADDR_BITS-1:0] w_word_addr = i_pc[ADDR_BITS+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, r_mem);
    end

    always @(posedge clock) begin
        if (i_we) r_mem[i_addr] <= i_wdata;
    end

    assign o_instr = r_mem[w_word_addr];

endmodule
