`timescale 1ns / 1ps

// Testbench de la etapa IF y el latch IF/ID (US-206; interfaz de US-303).
//
// - La IMEM se precarga por el puerto de la Debug Unit con un patron distinto por palabra, asi
//   cada instruccion en IF/ID dice de que direccion vino.
// - El testbench hace de hazard unit: maneja pc_sel, StallF, StallD y FlushD a mano. La
//   prioridad entre eventos la prueba tb_hazard_unit.
// - Casos: secuencial, load-use (StallF + StallD), FlushD solo, pc_sel = EX y = JAL, busqueda
//   detenida (StallF solo: HALT/ABORT), StallF con pc_sel = EX y FlushD (ABORT con redireccion),
//   i_enable = 0, vuelta de la IMEM fuera de rango y reset sin enable.
//
// Los estimulos se cambian en el flanco de bajada y se verifica despues del flanco de subida.
module tb_if_stage;
    `include "tb_utils.vh"

    localparam IMEM_DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam PERIODO = 10;
    localparam [31:0] NOP = 32'h0000_0013;
    localparam CICLOS_SIN_ENABLE = 50;
    localparam [1:0] PC_SEL_PLUS4 = 2'b00;
    localparam [1:0] PC_SEL_JAL = 2'b01;
    localparam [1:0] PC_SEL_EX = 2'b10;

    reg                  clock = 1'b0;
    reg                  r_reset = 1'b1;
    reg                  r_enable = 1'b0;
    // Lo que manda la hazard unit
    reg  [          1:0] r_pc_sel = PC_SEL_PLUS4;
    reg                  r_stall_f = 1'b0;
    reg                  r_stall_d = 1'b0;
    reg                  r_flush_d = 1'b0;
    reg  [         31:0] r_ex_pc = 0;
    reg  [         31:0] r_jal_pc = 0;
    // Carga de la IMEM
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

    // Copia del estado para el chequeo de enable
    reg  [         31:0] r_pc_antes;
    reg  [        103:0] r_if_id_antes;

    integer              k;
    integer              semilla = 206;

    if_stage #(
        .IMEM_DEPTH(IMEM_DEPTH)
    ) u_if_stage (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_stall_f   (r_stall_f),
        .i_pc_sel    (r_pc_sel),
        .i_ex_pc     (r_ex_pc),
        .i_jal_pc    (r_jal_pc),
        .o_pc        (w_pc_f),
        .o_pc_plus4  (w_pc_plus4_f),
        .o_instr     (w_instr_f),
        .o_valid     (w_valid_f),
        .i_imem_we   (r_imem_we),
        .i_imem_addr (r_imem_addr),
        .i_imem_wdata(r_imem_wdata)
    );

    if_id_reg u_if_id_reg (
        .clock     (clock),
        .i_reset   (r_reset),
        .i_enable  (r_enable),
        .i_flush   (r_flush_d),
        .i_stall   (r_stall_d),
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

    // Vuelve las senales de la hazard unit a "nada que hacer".
    task sin_eventos;
        begin
            r_pc_sel  = PC_SEL_PLUS4;
            r_stall_f = 1'b0;
            r_stall_d = 1'b0;
            r_flush_d = 1'b0;
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

        // ---- Secuencial: una instruccion por ciclo (0, 4, 8, ...) ----
        r_reset  = 1'b0;
        r_enable = 1'b1;
        for (k = 0; k < 10; k = k + 1) begin
            ciclo;
            ver_instr("IF/ID secuencial", 4 * k);
            check_eq("PC avanza", w_pc_f, 4 * k + 4);
        end
        // PC = 0x28, IF/ID = 0x24

        // ---- Load-use: StallF + StallD, PC e IF/ID se mantienen ----
        r_stall_f = 1'b1;
        r_stall_d = 1'b1;
        repeat (3) begin
            ciclo;
            check_eq("load-use: PC se mantiene", w_pc_f, 32'h0000_0028);
            ver_instr("load-use: IF/ID se mantiene", 32'h0000_0024);
        end
        sin_eventos;
        ciclo;
        ver_instr("sigue despues del stall", 32'h0000_0028);

        // ---- FlushD solo: burbuja en IF/ID, el PC sigue ----
        r_flush_d = 1'b1;
        ciclo;
        ver_burbuja("FlushD -> burbuja");
        check_eq("FlushD: el PC sigue", w_pc_f, 32'h0000_0030);
        sin_eventos;
        ciclo;
        ver_instr("despues del flush", 32'h0000_0030);
        // PC = 0x34

        // ---- pc_sel = EX con FlushD (redireccion de EX) ----
        r_pc_sel  = PC_SEL_EX;
        r_ex_pc   = 32'h0000_0100;
        r_jal_pc  = 32'h0000_0200;  // no se usa
        r_flush_d = 1'b1;
        ciclo;
        ver_burbuja("EX: lo de IF es burbuja");
        check_eq("EX: PC = destino de EX", w_pc_f, 32'h0000_0100);
        sin_eventos;
        ciclo;
        ver_instr("EX: busca el destino", 32'h0000_0100);

        // ---- pc_sel = JAL con FlushD (jal en ID), hacia atras ----
        r_pc_sel  = PC_SEL_JAL;
        r_jal_pc  = 32'h0000_0020;
        r_ex_pc   = 32'h0000_0300;  // no se usa
        r_flush_d = 1'b1;
        ciclo;
        ver_burbuja("jal: lo de IF es burbuja");
        check_eq("jal: PC = destino del jal", w_pc_f, 32'h0000_0020);
        sin_eventos;
        ciclo;
        ver_instr("jal: busca el destino", 32'h0000_0020);

        // ---- pc_sel = 11: no lo genera la hazard unit, se toma como + 4 ----
        r_pc_sel = 2'b11;
        ciclo;
        check_eq("pc_sel = 11: + 4", w_pc_f, 32'h0000_0028);
        sin_eventos;
        ciclo;
        // PC = 0x2c, IF/ID = 0x28

        // ---- StallF solo (HALT o ABORT): PC congelado y burbujas en IF/ID ----
        r_stall_f = 1'b1;
        repeat (3) begin
            ciclo;
            check_eq("StallF: PC congelado", w_pc_f, 32'h0000_002C);
            ver_burbuja("StallF: burbujas");
            check_eq("StallF: IF no valida", {31'd0, w_valid_f}, 32'd0);
        end
        // StallF con pc_sel = EX (ABORT con redireccion de EX): el PC no cambia
        r_pc_sel  = PC_SEL_EX;
        r_ex_pc   = 32'h0000_0060;
        r_flush_d = 1'b1;
        ciclo;
        check_eq("StallF + EX: PC quieto", w_pc_f, 32'h0000_002C);
        ver_burbuja("StallF + EX: burbuja");
        sin_eventos;
        ciclo;
        ver_instr("sin StallF: busca de nuevo", 32'h0000_002C);
        // PC = 0x30

        // ---- Con i_enable = 0 nada cambia, haga lo que haga la hazard unit ----
        r_enable      = 1'b0;
        r_pc_antes    = w_pc_f;
        r_if_id_antes = {w_valid_d, w_instr_d, w_pc_plus4_d, w_pc_d};
        for (k = 0; k < CICLOS_SIN_ENABLE; k = k + 1) begin
            r_pc_sel  = $random(semilla);
            r_stall_f = $random(semilla);
            r_stall_d = $random(semilla);
            r_flush_d = $random(semilla);
            r_ex_pc   = {$random(semilla)} & 32'hFFFF_FFFC;
            r_jal_pc  = {$random(semilla)} & 32'hFFFF_FFFC;
            ciclo;
            check_eq("enable 0: PC quieto", w_pc_f, r_pc_antes);
            check_eq("enable 0: IF/ID pc", w_pc_d, r_if_id_antes[31:0]);
            check_eq("enable 0: IF/ID pc_plus4", w_pc_plus4_d, r_if_id_antes[63:32]);
            check_eq("enable 0: IF/ID instr", w_instr_d, r_if_id_antes[95:64]);
            check_eq("enable 0: IF/ID valid", {31'd0, w_valid_d}, {31'd0, r_if_id_antes[96]});
        end
        sin_eventos;
        r_enable = 1'b1;
        ciclo;
        ver_instr("enable 0: sigue donde estaba", 32'h0000_0030);

        // ---- La IMEM da la vuelta fuera de rango ----
        r_pc_sel  = PC_SEL_EX;
        r_ex_pc   = 32'h0000_03FC;
        r_flush_d = 1'b1;
        ciclo;
        sin_eventos;
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
