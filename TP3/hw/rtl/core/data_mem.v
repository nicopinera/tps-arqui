//! @brief Memoria de datos (DMEM) del nucleo RV32I con bitmap de memoria usada
//!
//! Memoria distribuida (LUTRAM) inferida, de DEPTH palabras de 32 bits con write enable por
//! byte. Dos puertos de lectura combinacional (nucleo y Debug Unit) y un
//! unico puerto de escritura con mux (nucleo o limpieza de la Debug Unit).
//!
//! @details
//! - Escritura del nucleo: si i_we && i_valid && i_enable (R-EJ-6), escribe los bytes de
//!   i_wdata que marca i_be en la palabra i_addr[ADDR_BITS+1:2]. i_be e i_wdata llegan ya
//!   alineados. Los bits altos de la direccion se ignoran.
//! - Limpieza de la Debug Unit: si i_dbg_we, escribe ceros en la palabra i_dbg_wr_addr (los 4
//!   bytes) y NO marca el bitmap. Toma el puerto de escritura con prioridad: si coincide con
//!   un store del nucleo, el store no se hace. La Debug Unit solo la usa con i_enable = 0.
//! - Bitmap de memoria usada (flip-flops): un store del nucleo pone en 1 el bit de su palabra;
//!   si el bit pasa de 0 a 1, o_used_count se incrementa. i_clear_used pone ambos en 0,
//!   aunque i_enable = 0, y tiene prioridad sobre el store. En el core debe conectarse a
//!   i_reset || i_clear_used.
//! - Puerto de depuracion: o_dbg_data y o_dbg_used de la palabra i_dbg_addr (combinacional).
module data_mem #(
    parameter DEPTH = 256  //! Cantidad de palabras (DMEM_DEPTH)
) (
    input  wire                     clock,
    input  wire                     i_enable,       //! Clock enable del core
    input  wire                     i_clear_used,   //! Borra bitmap y contador
    // Puerto del nucleo (MEM)
    input  wire                     i_we,           //! mem_write de la instruccion en MEM
    input  wire                     i_valid,        //! valid de la instruccion en MEM
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [             31:0] i_addr,         //! Direccion de byte; se usan [ADDR_BITS+1:2]
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [              3:0] i_be,           //! Bytes a escribir (byte k = [8k+7:8k])
    input  wire [             31:0] i_wdata,        //! Dato ya alineado
    output wire [             31:0] o_rdata,        //! Palabra completa en i_addr
    // Puerto de la Debug Unit
    input  wire                     i_dbg_we,       //! Escribe ceros en mem[i_dbg_wr_addr]
    input  wire [$clog2(DEPTH)-1:0] i_dbg_wr_addr,  //! Direccion de palabra a limpiar
    input  wire [$clog2(DEPTH)-1:0] i_dbg_addr,     //! Direccion de palabra a leer
    output wire [             31:0] o_dbg_data,     //! mem[i_dbg_addr]
    output wire                     o_dbg_used,     //! Bit del bitmap de i_dbg_addr
    output wire [  $clog2(DEPTH):0] o_used_count    //! Palabras usadas (0 a DEPTH)
);

    reg [31:0] r_mem[0:DEPTH-1];
    localparam ADDR_BITS = $clog2(DEPTH);  // bits para direccionamiento
    localparam NBYTES = 4;  // bytes por palabra
    localparam BYTE_OFFSET_BITS = 2;  // bits bajos de la direccion: byte dentro de la palabra
    localparam [NBYTES-1:0] BE_TODOS = {NBYTES{1'b1}};
    localparam [NBYTES-1:0] BE_NINGUNO = {NBYTES{1'b0}};

    reg  [         31:0] r_mem                                                                                                  [0:DEPTH-1];
    //bitmap:
    reg  [    DEPTH-1:0] r_used;
    reg  [  ADDR_BITS:0] r_used_count;

    // Palabra que direcciona el nucleo
    wire [ADDR_BITS-1:0] w_core_addr = i_addr[ADDR_BITS+BYTE_OFFSET_BITS-1 : BYTE_OFFSET_BITS];

    // Store efectivo del nucleo: la misma condicion escribe la memoria y marca el bitmap.
    wire                 w_core_we = i_we && i_valid && i_enable && !i_dbg_we;

    wire [ADDR_BITS-1:0] w_wr_addr = i_dbg_we ? i_dbg_wr_addr : w_core_addr;  // Donde se escribe
    wire [         31:0] w_wr_data = i_dbg_we ? 32'h0000_0000 : i_wdata;  // Que se escribe
    wire [   NBYTES-1:0] w_wr_be = i_dbg_we ? BE_TODOS : (w_core_we ? i_be : BE_NINGUNO);  // Que bytes de la palabra se escribe

    // Escritura en memoria: escritura byte a byte dentro de la palabra
    always @(posedge clock) begin
        if (w_wr_be[0]) r_mem[w_wr_addr][7:0] <= w_wr_data[7:0];
        if (w_wr_be[1]) r_mem[w_wr_addr][15:8] <= w_wr_data[15:8];
        if (w_wr_be[2]) r_mem[w_wr_addr][23:16] <= w_wr_data[23:16];
        if (w_wr_be[3]) r_mem[w_wr_addr][31:24] <= w_wr_data[31:24];
    end

    // Bitmap y contador de palabras usadas
    always @(posedge clock) begin
        //Borrado de datos del bitmap
        if (i_clear_used) begin
            r_used       <= {DEPTH{1'b0}};
            r_used_count <= {(ADDR_BITS + 1) {1'b0}};
        end else if (w_core_we) begin
            // Marca como usada la posicion que se escribio
            r_used[w_core_addr] <= 1'b1;
            // Solo cuenta la primera escritura de cada palabra
            if (!r_used[w_core_addr]) r_used_count <= r_used_count + 1'b1;
        end
    end

    // Lectura de memoria
    assign o_rdata      = r_mem[w_core_addr];
    assign o_dbg_data   = r_mem[i_dbg_addr];
    assign o_dbg_used   = r_used[i_dbg_addr];
    assign o_used_count = r_used_count;

endmodule
