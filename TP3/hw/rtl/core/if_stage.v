//! @brief Etapa IF del nucleo: registro PC, mux de proximo PC e IMEM
//!
//! Busca una instruccion por ciclo en la IMEM (lectura combinacional) y calcula el
//! PC siguiente con las redirecciones de ID (jal) y de EX (branch tomado / jalr).
//!
//! @details
//! - Mux de proximo PC, con prioridad: redireccion de EX > redireccion de ID (jal) > pc + 4.
//! - El PC se actualiza con i_enable y sin i_stall ni i_halt_fetch. La redireccion de EX es la
//!   excepcion: actualiza el PC aunque i_stall o i_halt_fetch valgan 1 (un HALT en ID detras de
//!   un branch tomado era especulativo). Con i_enable = 0 nada cambia.
//! - El jal NO le gana a i_halt_fetch: en el core i_halt_fetch tambien lleva i_stop_fetch (ABORT),
//!   que congela el PC aunque haya un jal en ID.
//! - o_valid = !i_halt_fetch: con la busqueda detenida, a IF/ID entran burbujas. Los flushes
//!   los aplica if_id_reg (i_flush), no esta etapa.
//! - i_reset pone el PC en 0 aunque i_enable = 0. En el core se conecta i_reset || i_flush_all.
//! - Incluye la IMEM, con su puerto de escritura para la Debug Unit (no depende de i_enable).
module if_stage #(
    parameter IMEM_DEPTH = 256,  //! Palabras de la IMEM
    parameter INIT_FILE  = ""    //! .hex a precargar en la IMEM (solo simulacion)
) (
    input  wire                          clock,
    input  wire                          i_reset,           //! PC = 0, aunque i_enable = 0
    input  wire                          i_enable,          //! Clock enable del core
    input  wire                          i_stall,           //! Load-use: holdea el PC 1 ciclo (1 burbuja)
    input  wire                          i_halt_fetch,      //! HALT/ilegal en ID o ABORT: PC congelado, burbujas
    // Redirecciones
    input  wire                          i_redirect_ex,     //! Branch tomado o jalr en EX
    input  wire [                  31:0] i_redirect_ex_pc,  //! Destino calculado en EX (condicional o inc. calculando con inmm)
    input  wire                          i_redirect_jal,    //! jal valido en ID
    input  wire [                  31:0] i_jal_pc,          //! Destino del jal (salto incondicional)
    // Hacia IF/ID
    output wire [                  31:0] o_pc,              //! PC actual (direccion de la instruccion buscada)
    output wire [                  31:0] o_pc_plus4,
    output wire [                  31:0] o_instr,           //! IMEM[pc], combinacional
    output wire                          o_valid,           //! 0 = burbuja (busqueda detenida)
    // Carga de la IMEM (Debug Unit)
    input  wire                          i_imem_we,
    input  wire [$clog2(IMEM_DEPTH)-1:0] i_imem_addr,       //! Direccion de palabra
    input  wire [                  31:0] i_imem_wdata
);

    localparam [31:0] PC_RESET = 32'h0000_0000;
    localparam [31:0] PC_PASO  = 32'd4;

    reg  [31:0] r_pc;
    reg  [31:0] r_pc_next;

    wire [31:0] w_pc_plus4 = r_pc + PC_PASO;

    // El PC avanza con enable si no esta detenido; la redireccion de EX avanza igual.
    wire        w_pc_we = i_enable && (i_redirect_ex || (!i_stall && !i_halt_fetch));

    // Mux de proximo PC (prioridad EX > jal > +4)
    always @(*) begin
        r_pc_next = w_pc_plus4;
        if (i_redirect_ex) r_pc_next = i_redirect_ex_pc;
        else if (i_redirect_jal) r_pc_next = i_jal_pc;
    end

    always @(posedge clock) begin
        if (i_reset) r_pc <= PC_RESET;
        else if (w_pc_we) r_pc <= r_pc_next;
    end

    instr_mem #(
        .DEPTH    (IMEM_DEPTH),
        .INIT_FILE(INIT_FILE)
    ) u_instr_mem (
        .clock  (clock),
        .i_pc   (r_pc),
        .o_instr(o_instr),
        .i_we   (i_imem_we),
        .i_addr (i_imem_addr),
        .i_wdata(i_imem_wdata)
    );

    assign o_pc       = r_pc;
    assign o_pc_plus4 = w_pc_plus4;
    assign o_valid    = !i_halt_fetch;

endmodule
