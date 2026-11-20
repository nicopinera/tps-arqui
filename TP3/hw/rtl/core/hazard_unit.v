//! @brief Unidad de riesgos: load-use, flushes, halt_fetch y prioridades
//!
//! Decide, en cada ciclo, que hace cada parte del frente del pipeline (PC, IF/ID, ID/EX) y de
//! donde sale el proximo PC. Junta en un solo lugar todo el control de riesgos, como el datapath.
//!
//! @details
//! Eventos, de mayor a menor prioridad:
//! 1. Redireccion de EX (branch tomado o jalr): pc_sel = EX, flush de IF/ID e ID/EX. Gana a todo
//!    lo de ID (jal, load-use, HALT), porque la instruccion de ID era del camino equivocado.
//!    Con ABORT (i_stop_fetch) el PC no cambia: se descarta igual lo especulativo pero no se
//!    busca el destino.
//! 2. ABORT (i_stop_fetch): StallF (PC quieto, IF manda burbujas) y burbuja en ID/EX (se descarta
//!    la instruccion de ID). Lo que esta en EX, MEM y WB termina normalmente.
//! 3. jal en ID: pc_sel = JAL, flush de IF/ID.
//! 4. Load-use: load valido en EX, rd != x0 y la instruccion de ID lee ese registro (uses_rs1/
//!    uses_rs2). StallF + StallD (PC e IF/ID quietos) y burbuja en ID/EX. Dura un ciclo: al
//!    ciclo siguiente en EX hay una burbuja y la condicion deja de cumplirse.
//! 5. HALT/ilegal en ID (o ya detectado antes): StallF. IF manda burbujas hasta que el HALT se
//!    retira (o hasta un reset).
//!
//! halt_fetch es un registro: el HALT esta en ID un solo ciclo y la busqueda tiene que quedar
//! detenida despues. Lo borra una redireccion de EX (el HALT era especulativo y lo descarta el
//! flush). Con ABORT no se activa (el HALT de ID tambien se descarta).
//!
//! Todo es combinacional salvo r_halt_fetch: PC y latches actuan solo con i_enable.
module hazard_unit (
    input  wire       clock,
    input  wire       i_reset,           //! i_reset || i_flush_all
    input  wire       i_enable,          //! Enable efectivo del core
    // Load-use: instruccion en EX (ID/EX)
    input  wire       i_id_ex_valid,
    input  wire       i_id_ex_mem_read,  //! Es un load
    input  wire [4:0] i_id_ex_rd,
    // Load-use: instruccion en ID (IF/ID, decodificada en id_stage)
    input  wire [4:0] i_if_id_rs1,
    input  wire [4:0] i_if_id_rs2,
    input  wire       i_uses_rs1,        //! La instruccion de ID lee rs1
    input  wire       i_uses_rs2,        //! La instruccion de ID lee rs2
    // Eventos de control
    input  wire       i_redirect_ex,     //! Branch tomado o jalr valido en EX
    input  wire       i_redirect_jal,    //! jal valido en ID
    input  wire       i_halt_detected,   //! HALT o ilegal valido en ID
    input  wire       i_stop_fetch,      //! ABORT (Debug Unit)
    // Hacia IF y los latches (nombres del datapath)
    output reg  [1:0] o_pc_sel,          //! Proximo PC (PC_SEL_*)
    output reg        o_stall_f,         //! StallF: PC quieto, IF manda burbujas
    output reg        o_stall_d,         //! StallD: IF/ID se mantiene (load-use)
    output reg        o_flush_d,         //! FlushD: burbuja en IF/ID (redireccion)
    output reg        o_flush_e,         //! FlushE: burbuja en ID/EX por redireccion de EX
    output reg        o_bubble_e         //! Burbuja en ID/EX por load-use o ABORT
);

    `include "control_defs.vh"

    localparam [4:0] X0 = 5'd0;

    reg  r_halt_fetch;

    // Load valido en EX que escribe un registro distinto de x0
    wire w_load_en_ex = i_id_ex_valid && i_id_ex_mem_read && (i_id_ex_rd != X0);

    // La instruccion de ID necesita el registro que carga el load
    wire w_usa_rd = (i_uses_rs1 && (i_if_id_rs1 == i_id_ex_rd)) || (i_uses_rs2 && (i_if_id_rs2 == i_id_ex_rd));

    wire w_load_use = w_load_en_ex && w_usa_rd;

    // Busqueda detenida por un HALT/ilegal: el de este ciclo en ID o uno detectado antes
    wire w_halt_fetch = r_halt_fetch || i_halt_detected;

    // halt_fetch pegajoso
    always @(posedge clock) begin
        if (i_reset) begin
            r_halt_fetch <= 1'b0;
        end else if (i_enable) begin
            if (i_redirect_ex) r_halt_fetch <= 1'b0;
            else if (i_halt_detected && !i_stop_fetch) r_halt_fetch <= 1'b1;
        end
    end

    // Tabla de prioridades
    always @(*) begin
        o_pc_sel   = PC_SEL_PLUS4;
        o_stall_f  = 1'b0;
        o_stall_d  = 1'b0;
        o_flush_d  = 1'b0;
        o_flush_e  = 1'b0;
        o_bubble_e = 1'b0;
        if (i_redirect_ex) begin
            // 1. Redireccion de EX: lo de IF e ID era especulativo
            o_pc_sel  = PC_SEL_EX;
            o_flush_d = 1'b1;  // Flush IF/ID: burbuja en lugar de la instruccion de IF
            o_flush_e = 1'b1;  // Flush ID/EX: burbuja en lugar de la instruccion de ID
            o_stall_f = i_stop_fetch;  // con ABORT no se busca el destino
        end else if (i_stop_fetch) begin
            // 2. ABORT: deja de buscar y descarta la instruccion de ID
            o_stall_f  = 1'b1;  // StallF: PC quieto, IF manda burbujas a IF/ID
            o_bubble_e = 1'b1;  // Burbuja en ID/EX: se descarta la instruccion de ID
        end else if (i_redirect_jal) begin
            // 3. jal en ID
            o_pc_sel  = PC_SEL_JAL;
            o_flush_d = 1'b1;  // Flush IF/ID: burbuja en lugar de la instruccion de IF
        end else if (w_load_use) begin
            // 4. Load-use: la instruccion de ID espera un ciclo
            o_stall_f  = 1'b1;  // StallF: PC quieto
            o_stall_d  = 1'b1;  // StallD: IF/ID mantiene la instruccion que espera
            o_bubble_e = 1'b1;  // Burbuja en ID/EX para no duplicarla en EX
        end else if (w_halt_fetch) begin
            // 5. HALT/ilegal: deja de buscar
            o_stall_f = 1'b1;  // StallF: PC quieto, IF manda burbujas a IF/ID
        end
    end

endmodule
