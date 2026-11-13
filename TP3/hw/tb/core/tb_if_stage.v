`timescale 1ns / 1ps

// Testbench de la etapa IF y el latch IF/ID (US-206, AC1 a AC6).
//
// - La IMEM se precarga por el puerto de la Debug Unit con un patron distinto por palabra, asi
//   cada instruccion en IF/ID dice de que direccion vino.
// - El flush de IF/ID se arma como lo va a hacer riscv_core en el Hito 2 (flush basico):
//   flush_if_id = redirect_ex || redirect_jal. r_flush agrega un flush suelto para el AC3.
// - Ademas de los AC: halt_fetch (PC congelado y burbujas, salvo redireccion de EX), reset con
//   i_enable = 0 y la vuelta de la IMEM fuera de rango (ADR-008).
//
// Los estimulos se cambian en el flanco de bajada y se verifica despues del flanco de subida.
module tb_if_stage;
    `include "tb_utils.vh"

    localparam IMEM_DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam PERIODO = 10;
    localparam [31:0] NOP = 32'h0000_0013;
    localparam CICLOS_SIN_ENABLE = 50;

    reg                  clock = 1'b0;
    reg                  r_reset = 1'b1;
    reg                  r_enable = 1'b0;
    reg                  r_stall = 1'b0;
    reg                  r_halt_fetch = 1'b0;
    reg                  r_flush = 1'b0;
    reg                  r_redirect_ex = 1'b0;
    reg  [         31:0] r_redirect_ex_pc = 0;
    reg                  r_redirect_jal = 1'b0;
    reg  [         31:0] r_jal_pc = 0;
    reg                  r_imem_we = 1'b0;
    reg  [ADDR_BITS-1:0] r_imem_addr = 0;
    reg  [         31:0] r_imem_wdata = 0;

    // IF -> IF/ID
    wire [         31:0] w_pc_f;
    wire [         31:0] w_pc_plus4_f;
    wire [         31:0] w_instr_f;
    wire                 w_valid_f;
    // Salida de IF/ID
    wire [         31:0] w_pc_d;
    wire [         31:0] w_pc_plus4_d;
    wire [         31:0] w_instr_d;
    wire                 w_valid_d;

    // Flush basico del Hito 2, mas un flush suelto
    wire                 w_flush_if_id = r_flush || r_redirect_ex || r_redirect_jal;

    // Copia del estado para el AC4
    reg  [         31:0] r_pc_antes;
    reg  [        103:0] r_if_id_antes;

    integer              k;
    integer              semilla = 206;

    if_stage #(
        .IMEM_DEPTH(IMEM_DEPTH)
    ) u_if_stage (
        .clock           (clock),
        .i_reset         (r_reset),
        .i_enable        (r_enable),
        .i_stall         (r_stall),
        .i_halt_fetch    (r_halt_fetch),
        .i_redirect_ex   (r_redirect_ex),
        .i_redirect_ex_pc(r_redirect_ex_pc),
        .i_redirect_jal  (r_redirect_jal),
        .i_jal_pc        (r_jal_pc),
        .o_pc            (w_pc_f),
        .o_pc_plus4      (w_pc_plus4_f),
        .o_instr         (w_instr_f),
        .o_valid         (w_valid_f),
        .i_imem_we       (r_imem_we),
        .i_imem_addr     (r_imem_addr),
        .i_imem_wdata    (r_imem_wdata)
    );

    if_id_reg u_if_id_reg (
        .clock     (clock),
        .i_reset   (r_reset),
        .i_enable  (r_enable),
        .i_flush   (w_flush_if_id),
        .i_stall   (r_stall),
        .i_pc      (w_pc_f),
        .i_pc_plus4(w_pc_plus4_f),
        .i_instr   (w_instr_f),
        .i_valid   (w_valid_f),
        .o_pc      (w_pc_d),
        .o_pc_plus4(w_pc_plus4_d),
        .o_instr   (w_instr_d),
        .o_valid   (w_valid_d)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Palabra k de la IMEM: distinta en cada direccion y nunca igual al NOP.
    function [31:0] patron;
        input integer indice;
        begin
            patron = {8'hA5, indice[7:0], ~indice[7:0], 8'h3C};
        end
    endfunction

    // Un ciclo de reloj: flanco de subida y vuelta al de bajada para cambiar estimulos.
    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    // Verifica una instruccion valida en IF/ID que vino de la direccion pc.
    task ver_instr;
        input [255:0] nombre;
        input [31:0] pc;
        begin
            check_eq(nombre, w_pc_d, pc);
            check_eq(nombre, w_pc_plus4_d, pc + 4);
            check_eq(nombre, w_instr_d, patron(pc[ADDR_BITS+1:2]));
            check_eq(nombre, {31'd0, w_valid_d}, 32'd1);
        end
    endtask

    // Verifica que en IF/ID haya una burbuja.
    task ver_burbuja;
        input [255:0] nombre;
        begin
            check_eq(nombre, {31'd0, w_valid_d}, 32'd0);
            check_eq(nombre, w_instr_d, NOP);
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);

        // ---- Carga de la IMEM por el puerto de la Debug Unit (con el core en reset) ----
        r_imem_we = 1'b1;
        for (k = 0; k < IMEM_DEPTH; k = k + 1) begin
            r_imem_addr  = k[ADDR_BITS-1:0];
            r_imem_wdata = patron(k);
            ciclo;
        end
        r_imem_we = 1'b0;

        check_eq("reset: PC = 0", w_pc_f, 32'h0000_0000);
        ver_burbuja("reset: IF/ID vacio");

        // ---- AC1: sin stalls ni saltos, una instruccion por ciclo (0, 4, 8, ...) ----
        r_reset  = 1'b0;
        r_enable = 1'b1;
        for (k = 0; k < 10; k = k + 1) begin
            ciclo;
            ver_instr("AC1 IF/ID secuencial", 4 * k);
            check_eq("AC1 PC avanza", w_pc_f, 4 * k + 4);
        end
        // PC = 0x28, IF/ID = 0x24

        // ---- AC2: con stall, PC e IF/ID se mantienen ----
        r_stall = 1'b1;
        repeat (3) begin
            ciclo;
            check_eq("AC2 PC se mantiene", w_pc_f, 32'h0000_0028);
            ver_instr("AC2 IF/ID se mantiene", 32'h0000_0024);
        end
        r_stall = 1'b0;
        ciclo;
        ver_instr("AC2 sigue despues del stall", 32'h0000_0028);

        // ---- AC3: flush suelto -> burbuja en IF/ID en el ciclo siguiente ----
        // El flush solo no detiene el PC: la siguiente se busca normalmente.
        r_flush = 1'b1;
        ciclo;
        ver_burbuja("AC3 flush -> burbuja");
        check_eq("AC3 el PC sigue", w_pc_f, 32'h0000_0030);
        r_flush = 1'b0;
        ciclo;
        ver_instr("AC3 despues del flush", 32'h0000_0030);
        // PC = 0x34

        // ---- AC5: redireccion de EX ----
        r_redirect_ex    = 1'b1;
        r_redirect_ex_pc = 32'h0000_0100;
        ciclo;
        ver_burbuja("AC5 EX: lo de IF es burbuja");
        check_eq("AC5 EX: PC = destino", w_pc_f, 32'h0000_0100);
        r_redirect_ex = 1'b0;
        ciclo;
        ver_instr("AC5 EX: busca el destino", 32'h0000_0100);

        // ---- AC5: redireccion de ID (jal), hacia atras ----
        r_redirect_jal = 1'b1;
        r_jal_pc       = 32'h0000_0020;
        ciclo;
        ver_burbuja("AC5 jal: lo de IF es burbuja");
        check_eq("AC5 jal: PC = destino", w_pc_f, 32'h0000_0020);
        r_redirect_jal = 1'b0;
        ciclo;
        ver_instr("AC5 jal: busca el destino", 32'h0000_0020);

        // ---- AC6: EX y jal en el mismo ciclo -> gana EX ----
        r_redirect_ex    = 1'b1;
        r_redirect_ex_pc = 32'h0000_0080;
        r_redirect_jal   = 1'b1;
        r_jal_pc         = 32'h0000_0200;
        ciclo;
        ver_burbuja("AC6 burbuja");
        check_eq("AC6 gana EX", w_pc_f, 32'h0000_0080);
        r_redirect_ex  = 1'b0;
        r_redirect_jal = 1'b0;
        ciclo;
        ver_instr("AC6 busca el destino de EX", 32'h0000_0080);
        // PC = 0x84

        // ---- Redireccion de EX durante un stall: el PC se redirige igual y gana el flush ----
        r_stall          = 1'b1;
        r_redirect_ex    = 1'b1;
        r_redirect_ex_pc = 32'h0000_0040;
        ciclo;
        check_eq("stall + EX: PC = destino", w_pc_f, 32'h0000_0040);
        ver_burbuja("stall + EX: flush le gana");
        r_stall       = 1'b0;
        r_redirect_ex = 1'b0;
        ciclo;
        ver_instr("stall + EX: busca el destino", 32'h0000_0040);
        // PC = 0x44

        // ---- halt_fetch: PC congelado y burbujas en IF/ID ----
        r_halt_fetch = 1'b1;
        repeat (3) begin
            ciclo;
            check_eq("halt_fetch: PC congelado", w_pc_f, 32'h0000_0044);
            ver_burbuja("halt_fetch: burbujas");
        end
        // Un jal no mueve el PC con halt_fetch (es el caso de ABORT)
        r_redirect_jal = 1'b1;
        r_jal_pc       = 32'h0000_0010;
        ciclo;
        check_eq("halt_fetch + jal: PC quieto", w_pc_f, 32'h0000_0044);
        r_redirect_jal = 1'b0;
        // Una redireccion de EX si lo mueve (el HALT era especulativo)
        r_redirect_ex    = 1'b1;
        r_redirect_ex_pc = 32'h0000_0060;
        ciclo;
        check_eq("halt_fetch + EX: PC = destino", w_pc_f, 32'h0000_0060);
        ver_burbuja("halt_fetch + EX: burbuja");
        r_redirect_ex = 1'b0;
        ciclo;
        check_eq("halt_fetch + EX: despues, quieto", w_pc_f, 32'h0000_0060);
        ver_burbuja("halt_fetch: sigue con burbujas");
        r_halt_fetch = 1'b0;
        ciclo;
        ver_instr("sin halt_fetch: busca de nuevo", 32'h0000_0060);
        // PC = 0x64

        // ---- AC4: con i_enable = 0 nada cambia, haga lo que haga el resto ----
        r_enable      = 1'b0;
        r_pc_antes    = w_pc_f;
        r_if_id_antes = {w_valid_d, w_instr_d, w_pc_plus4_d, w_pc_d};
        for (k = 0; k < CICLOS_SIN_ENABLE; k = k + 1) begin
            r_stall          = $random(semilla);
            r_halt_fetch     = $random(semilla);
            r_flush          = $random(semilla);
            r_redirect_ex    = $random(semilla);
            r_redirect_ex_pc = {$random(semilla)} & 32'hFFFF_FFFC;
            r_redirect_jal   = $random(semilla);
            r_jal_pc         = {$random(semilla)} & 32'hFFFF_FFFC;
            ciclo;
            check_eq("AC4 PC quieto", w_pc_f, r_pc_antes);
            check_eq("AC4 IF/ID pc", w_pc_d, r_if_id_antes[31:0]);
            check_eq("AC4 IF/ID pc_plus4", w_pc_plus4_d, r_if_id_antes[63:32]);
            check_eq("AC4 IF/ID instr", w_instr_d, r_if_id_antes[95:64]);
            check_eq("AC4 IF/ID valid", {31'd0, w_valid_d}, {31'd0, r_if_id_antes[96]});
        end
        r_stall        = 1'b0;
        r_halt_fetch   = 1'b0;
        r_flush        = 1'b0;
        r_redirect_ex  = 1'b0;
        r_redirect_jal = 1'b0;
        r_enable       = 1'b1;
        ciclo;
        ver_instr("AC4 sigue donde estaba", 32'h0000_0064);

        // ---- La IMEM da la vuelta fuera de rango (ADR-008) ----
        r_redirect_ex    = 1'b1;
        r_redirect_ex_pc = 32'h0000_03FC;
        ciclo;
        r_redirect_ex = 1'b0;
        ciclo;
        ver_instr("ultima palabra (0x3FC)", 32'h0000_03FC);
        ciclo;
        check_eq("0x400: pc", w_pc_d, 32'h0000_0400);
        check_eq("0x400: lee la palabra 0", w_instr_d, patron(0));

        // ---- El reset actua aunque i_enable = 0 ----
        r_enable = 1'b0;
        r_reset  = 1'b1;
        ciclo;
        check_eq("reset sin enable: PC = 0", w_pc_f, 32'h0000_0000);
        ver_burbuja("reset sin enable: IF/ID vacio");
        r_reset  = 1'b0;
        r_enable = 1'b1;
        ciclo;
        ver_instr("despues del reset: arranca en 0", 32'h0000_0000);

        tb_finish;
    end
endmodule
