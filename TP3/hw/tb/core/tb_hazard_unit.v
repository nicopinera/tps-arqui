`timescale 1ns / 1ps

// Testbench de la unidad de riesgos (US-302 y US-303).
//
// - Load-use: load seguido de una instruccion que usa su rd en rs1 o rs2 (stall), que no lo
//   usa, que tiene esos bits pero no los lee (uses_rs = 0), load a x0, burbuja en EX e
//   instruccion que no es load en EX.
// - Prioridades: cada evento solo y los pares que pueden coincidir (EX con jal, con load-use,
//   con HALT y con ABORT; ABORT con jal, load-use y HALT).
// - halt_fetch: se activa con un HALT en ID y queda activo; lo borra una redireccion de EX o
//   el reset; con ABORT no se activa; con i_enable = 0 no cambia.
// - Aleatorio: entradas al azar en cada ciclo contra un modelo de referencia que lleva su propio
//   halt_fetch.
//
// Los estimulos se cambian en el flanco de bajada; las salidas (combinacionales) se miran antes
// del flanco de subida.
module tb_hazard_unit;
    `include "tb_utils.vh"

    localparam PERIODO = 10;
    localparam N_ALEATORIOS = 5000;
    localparam [1:0] PC_SEL_PLUS4 = 2'b00;
    localparam [1:0] PC_SEL_JAL = 2'b01;
    localparam [1:0] PC_SEL_EX = 2'b10;

    reg        clock = 1'b0;
    reg        r_reset = 1'b1;
    reg        r_enable = 1'b0;
    // Load-use
    reg        r_valid = 0;
    reg        r_mem_read = 0;
    reg  [4:0] r_rd = 0;
    reg  [4:0] r_rs1 = 0;
    reg  [4:0] r_rs2 = 0;
    reg        r_uses_rs1 = 0;
    reg        r_uses_rs2 = 0;
    // Eventos de control
    reg        r_redirect_ex = 0;
    reg        r_redirect_jal = 0;
    reg        r_halt_detected = 0;
    reg        r_stop_fetch = 0;

    wire [1:0] w_pc_sel;
    wire       w_stall_f;
    wire       w_stall_d;
    wire       w_flush_d;
    wire       w_flush_e;
    wire       w_bubble_e;

    // Salidas juntas: {pc_sel, stall_f, stall_d, flush_d, flush_e, bubble_e}
    wire [6:0] w_salidas = {w_pc_sel, w_stall_f, w_stall_d, w_flush_d, w_flush_e, w_bubble_e};

    // halt_fetch del modelo de referencia
    reg        r_ref_halt_fetch = 1'b0;

    integer    k;
    integer    semilla = 303;

    hazard_unit u_hazard_unit (
        .clock           (clock),
        .i_reset         (r_reset),
        .i_enable        (r_enable),
        .i_id_ex_valid   (r_valid),
        .i_id_ex_mem_read(r_mem_read),
        .i_id_ex_rd      (r_rd),
        .i_if_id_rs1     (r_rs1),
        .i_if_id_rs2     (r_rs2),
        .i_uses_rs1      (r_uses_rs1),
        .i_uses_rs2      (r_uses_rs2),
        .i_redirect_ex   (r_redirect_ex),
        .i_redirect_jal  (r_redirect_jal),
        .i_halt_detected (r_halt_detected),
        .i_stop_fetch    (r_stop_fetch),
        .o_pc_sel        (w_pc_sel),
        .o_stall_f       (w_stall_f),
        .o_stall_d       (w_stall_d),
        .o_flush_d       (w_flush_d),
        .o_flush_e       (w_flush_e),
        .o_bubble_e      (w_bubble_e)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Modelo de referencia: arma las salidas evento por evento, sin la cadena de prioridades
    function [6:0] salidas_ref;
        input dummy;
        reg load_use, halt_fetch, jal;
        reg [1:0] pc_sel;
        reg stall_f, stall_d, flush_d, flush_e, bubble_e;
        begin
            load_use   = r_valid && r_mem_read && (r_rd != 0) &&
                         ((r_uses_rs1 && r_rs1 == r_rd) || (r_uses_rs2 && r_rs2 == r_rd));
            halt_fetch = r_ref_halt_fetch || r_halt_detected;
            // jal y load-use solo cuentan si no hay redireccion de EX ni ABORT
            jal        = r_redirect_jal && !r_redirect_ex && !r_stop_fetch;
            load_use   = load_use && !r_redirect_ex && !r_stop_fetch && !jal;
            pc_sel     = r_redirect_ex ? PC_SEL_EX : (jal ? PC_SEL_JAL : PC_SEL_PLUS4);
            flush_d    = r_redirect_ex || jal;
            flush_e    = r_redirect_ex;
            stall_d    = load_use;
            bubble_e   = !r_redirect_ex && (r_stop_fetch || load_use);
            stall_f    = r_redirect_ex ? r_stop_fetch :
                         (r_stop_fetch || (!jal && (load_use || halt_fetch)));
            salidas_ref = {pc_sel, stall_f, stall_d, flush_d, flush_e, bubble_e};
        end
    endfunction

    // halt_fetch del modelo en cada flanco
    always @(posedge clock) begin
        if (r_reset) r_ref_halt_fetch <= 1'b0;
        else if (r_enable) begin
            if (r_redirect_ex) r_ref_halt_fetch <= 1'b0;
            else if (r_halt_detected && !r_stop_fetch) r_ref_halt_fetch <= 1'b1;
        end
    end

    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    task sin_eventos;
        begin
            r_valid         = 1'b0;
            r_mem_read      = 1'b0;
            r_rd            = 5'd0;
            r_rs1           = 5'd0;
            r_rs2           = 5'd0;
            r_uses_rs1      = 1'b0;
            r_uses_rs2      = 1'b0;
            r_redirect_ex   = 1'b0;
            r_redirect_jal  = 1'b0;
            r_halt_detected = 1'b0;
            r_stop_fetch    = 1'b0;
        end
    endtask

    // Load valido en EX (rd = rd_load) e instruccion en ID con sus rs y uses_rs.
    task load_use;
        input [4:0] rd_load;
        input [4:0] rs1;
        input [4:0] rs2;
        input uses_rs1;
        input uses_rs2;
        begin
            r_valid    = 1'b1;
            r_mem_read = 1'b1;
            r_rd       = rd_load;
            r_rs1      = rs1;
            r_rs2      = rs2;
            r_uses_rs1 = uses_rs1;
            r_uses_rs2 = uses_rs2;
        end
    endtask

    // Compara las 7 salidas: {pc_sel, stall_f, stall_d, flush_d, flush_e, bubble_e}
    task ver;
        input [255:0] nombre;
        input [6:0] esperado;
        begin
            #1 check_eq(nombre, {25'd0, w_salidas}, {25'd0, esperado});
        end
    endtask

    // Salidas esperadas de cada situacion
    localparam [6:0] NADA = {PC_SEL_PLUS4, 5'b00000};
    localparam [6:0] LOAD_USE = {PC_SEL_PLUS4, 5'b11001};
    localparam [6:0] REDIR_EX = {PC_SEL_EX, 5'b00110};
    localparam [6:0] REDIR_EX_ABORT = {PC_SEL_EX, 5'b10110};
    localparam [6:0] JAL = {PC_SEL_JAL, 5'b00100};
    localparam [6:0] ABORT = {PC_SEL_PLUS4, 5'b10001};
    localparam [6:0] HALT = {PC_SEL_PLUS4, 5'b10000};

    initial begin
        tb_init;
        @(negedge clock);
        r_reset  = 1'b0;
        r_enable = 1'b1;
        sin_eventos;
        ver("sin eventos", NADA);

        // ---- Load-use ----
        load_use(5'd1, 5'd1, 5'd4, 1, 1);
        ver("lw x1 + add x3,x1,x4", LOAD_USE);
        load_use(5'd1, 5'd4, 5'd1, 1, 1);
        ver("lw x1 + add x3,x4,x1", LOAD_USE);
        load_use(5'd1, 5'd2, 5'd1, 1, 1);
        ver("lw x1 + sw x1,0(x2)", LOAD_USE);
        load_use(5'd1, 5'd1, 5'd5, 1, 0);
        ver("lw x1 + addi x3,x1,5", LOAD_USE);
        load_use(5'd1, 5'd4, 5'd5, 1, 1);
        ver("lw x1 + independiente", NADA);
        load_use(5'd5, 5'd3, 5'd5, 1, 0);
        ver("lw x5 + addi (imm 5)", NADA);
        load_use(5'd1, 5'd1, 5'd1, 0, 0);
        ver("lw x1 + lui x1", NADA);
        load_use(5'd0, 5'd0, 5'd0, 1, 1);
        ver("lw x0 + add x5,x0,x0", NADA);
        load_use(5'd1, 5'd1, 5'd1, 1, 1);
        r_mem_read = 1'b0;
        ver("add x1 en EX: no frena", NADA);
        load_use(5'd1, 5'd1, 5'd1, 1, 1);
        r_valid = 1'b0;
        ver("burbuja en EX: no frena", NADA);
        sin_eventos;

        // ---- Cada evento de control solo ----
        r_redirect_ex = 1'b1;
        ver("redireccion de EX", REDIR_EX);
        sin_eventos;
        r_redirect_jal = 1'b1;
        ver("jal en ID", JAL);
        sin_eventos;
        r_stop_fetch = 1'b1;
        ver("ABORT", ABORT);
        sin_eventos;

        // ---- Prioridades ----
        // EX le gana al jal de ID (el jal era especulativo)
        r_redirect_ex  = 1'b1;
        r_redirect_jal = 1'b1;
        ver("EX + jal: gana EX", REDIR_EX);
        sin_eventos;
        // EX le gana al load-use (no coinciden en el nucleo: por las dudas)
        load_use(5'd1, 5'd1, 5'd4, 1, 1);
        r_redirect_ex = 1'b1;
        ver("EX + load-use: gana EX", REDIR_EX);
        sin_eventos;
        // EX le gana al HALT de ID (HALT especulativo)
        r_halt_detected = 1'b1;
        r_redirect_ex   = 1'b1;
        ver("EX + HALT: gana EX", REDIR_EX);
        sin_eventos;
        // EX con ABORT: se descarta lo especulativo pero el PC no cambia
        r_redirect_ex = 1'b1;
        r_stop_fetch  = 1'b1;
        ver("EX + ABORT: PC quieto", REDIR_EX_ABORT);
        sin_eventos;
        // ABORT le gana al jal, al load-use y al HALT
        r_redirect_jal = 1'b1;
        r_stop_fetch   = 1'b1;
        ver("ABORT + jal: gana ABORT", ABORT);
        sin_eventos;
        load_use(5'd1, 5'd1, 5'd4, 1, 1);
        r_stop_fetch = 1'b1;
        ver("ABORT + load-use: gana ABORT", ABORT);
        sin_eventos;
        r_halt_detected = 1'b1;
        r_stop_fetch    = 1'b1;
        ver("ABORT + HALT: gana ABORT", ABORT);
        sin_eventos;

        // ---- halt_fetch ----
        r_halt_detected = 1'b1;
        ver("HALT en ID: StallF", HALT);
        ciclo;
        r_halt_detected = 1'b0;
        ver("HALT ya en EX: sigue detenida", HALT);
        ciclo;
        ver("varios ciclos despues: sigue", HALT);
        // Con i_enable = 0 no cambia, aunque EX redirija
        r_enable      = 1'b0;
        r_redirect_ex = 1'b1;
        ciclo;
        r_redirect_ex = 1'b0;
        ver("enable 0: halt_fetch no cambia", HALT);
        r_enable = 1'b1;
        // Una redireccion de EX la borra
        r_redirect_ex = 1'b1;
        ciclo;
        r_redirect_ex = 1'b0;
        ver("EX borra halt_fetch", NADA);
        // HALT y redireccion de EX en el mismo ciclo: no queda activa
        r_halt_detected = 1'b1;
        r_redirect_ex   = 1'b1;
        ciclo;
        sin_eventos;
        ver("HALT + EX: no queda activa", NADA);
        // Con ABORT un HALT no la activa
        r_halt_detected = 1'b1;
        r_stop_fetch    = 1'b1;
        ciclo;
        sin_eventos;
        ver("HALT con ABORT: no se activa", NADA);
        // El reset la borra
        r_halt_detected = 1'b1;
        ciclo;
        r_halt_detected = 1'b0;
        ver("HALT: activa", HALT);
        r_reset = 1'b1;
        ciclo;
        r_reset = 1'b0;
        ver("reset la borra", NADA);

        // ---- Aleatorio contra el modelo ----
        for (k = 0; k < N_ALEATORIOS; k = k + 1) begin
            r_enable        = ($random(semilla) & 7) != 0;
            r_valid         = $random(semilla);
            r_mem_read      = $random(semilla);
            r_rd            = $random(semilla) & 5'd3;
            r_rs1           = $random(semilla) & 5'd3;
            r_rs2           = $random(semilla) & 5'd3;
            r_uses_rs1      = $random(semilla);
            r_uses_rs2      = $random(semilla);
            r_redirect_ex   = ($random(semilla) & 3) == 0;
            r_redirect_jal  = ($random(semilla) & 3) == 0;
            r_halt_detected = ($random(semilla) & 7) == 0;
            r_stop_fetch    = ($random(semilla) & 7) == 0;
            #1 check_eq("aleatorio", {25'd0, w_salidas}, {25'd0, salidas_ref(1'b0)});
            ciclo;
        end

        tb_finish;
    end
endmodule
