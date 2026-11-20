`timescale 1ns / 1ps

// Testbench de las etapas MEM y WB y el latch MEM/WB (US-209, AC1 a AC3).
//
// Conecta mem_stage -> mem_wb_reg -> wb_stage como en el pipeline. El testbench hace de EX/MEM:
// maneja direccion, dato del store, funct3 y las senales de control a mano.
//
// - Arranque como en un LOAD: limpia la DMEM y el bitmap por los puertos de la Debug Unit.
// - Stores (sw, sb, sh) verificados por el puerto de lectura de la Debug Unit, con el bit de
//   usada y el contador.
// - AC1: lw/lb/lbu/lh/lhu escriben en rd el dato de memoria extendido; add el de la ALU; jal
//   el pc + 4.
// - AC2: un store no escribe el banco (o_wb_we = 0).
// - AC3: o_halt_retired dura exactamente el ciclo en que el HALT (o la ilegal) esta en WB;
//   o_illegal_retired distingue los dos casos; sin valid no se retira nada.
// - Ademas: burbuja (no escribe memoria ni banco), store con i_enable = 0, MEM/WB congelado,
//   reset sin enable y DEBUG_TRACE = 0.
//
// Los estimulos se cambian en el flanco de bajada; MEM se mira antes del flanco de subida y
// MEM/WB y WB despues.
module tb_mem_wb;
    `include "tb_utils.vh"

    localparam PERIODO = 10;
    localparam DMEM_DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam CICLOS_SIN_ENABLE = 20;
    localparam [31:0] NOP = 32'h0000_0013;

    // funct3 y result_src
    localparam [2:0] F3_B = 3'b000;  // lb / sb
    localparam [2:0] F3_H = 3'b001;  // lh / sh
    localparam [2:0] F3_W = 3'b010;  // lw / sw
    localparam [2:0] F3_BU = 3'b100;  // lbu
    localparam [2:0] F3_HU = 3'b101;  // lhu
    localparam [1:0] RES_ALU = 2'b00;
    localparam [1:0] RES_MEM = 2'b01;
    localparam [1:0] RES_PC4 = 2'b10;

    reg                  clock = 1'b0;
    reg                  r_reset = 1'b1;
    reg                  r_enable = 1'b0;
    // EX/MEM (lo maneja el testbench)
    reg  [         31:0] r_alu_result = 0;
    reg  [         31:0] r_store_data = 0;
    reg  [         31:0] r_pc_plus4 = 0;
    reg  [          4:0] r_rd = 0;
    reg  [          2:0] r_funct3 = 0;
    reg                  r_reg_write = 0;
    reg                  r_mem_write = 0;
    reg  [          1:0] r_result_src = 0;
    reg                  r_halt = 0;
    reg                  r_illegal = 0;
    reg                  r_valid = 0;
    reg  [         31:0] r_instr = NOP;
    // Debug Unit
    reg                  r_dbg_dmem_we = 0;
    reg  [ADDR_BITS-1:0] r_dbg_dmem_addr = 0;
    reg                  r_clear_used = 0;
    reg  [ADDR_BITS-1:0] r_dbg_mem_addr = 0;
    wire [         31:0] w_dbg_mem_data;
    wire                 w_dbg_mem_used;
    wire [  ADDR_BITS:0] w_dbg_used_count;

    // MEM
    wire [         31:0] w_mem_data;

    // MEM/WB
    wire [         31:0] b_alu_result;
    wire [         31:0] b_mem_data;
    wire [         31:0] b_pc_plus4;
    wire [          4:0] b_rd;
    wire                 b_reg_write;
    wire [          1:0] b_result_src;
    wire                 b_halt;
    wire                 b_illegal;
    wire                 b_valid;
    wire [         31:0] b_instr;
    wire [         31:0] b_instr_sin_trace;

    // WB
    wire                 w_wb_we;
    wire [          4:0] w_wb_rd;
    wire [         31:0] w_wb_data;
    wire                 w_halt_retired;
    wire                 w_illegal_retired;

    // Copia de MEM/WB para el chequeo de enable
    reg  [         31:0] r_antes_wb_data;
    reg  [         31:0] r_antes_instr;
    reg  [          5:0] r_antes_ctrl;
    wire [          5:0] b_ctrl = {b_reg_write, b_result_src, b_halt, b_illegal, b_valid};

    integer              k;
    integer              semilla = 209;

    mem_stage #(
        .DMEM_DEPTH(DMEM_DEPTH)
    ) u_mem_stage (
        .clock           (clock),
        .i_enable        (r_enable),
        .i_alu_result    (r_alu_result),
        .i_store_data    (r_store_data),
        .i_funct3        (r_funct3),
        .i_mem_write     (r_mem_write),
        .i_valid         (r_valid),
        .o_mem_data      (w_mem_data),
        .i_dbg_dmem_we   (r_dbg_dmem_we),
        .i_dbg_dmem_addr (r_dbg_dmem_addr),
        .i_clear_used    (r_clear_used),
        .i_dbg_mem_addr  (r_dbg_mem_addr),
        .o_dbg_mem_data  (w_dbg_mem_data),
        .o_dbg_mem_used  (w_dbg_mem_used),
        .o_dbg_used_count(w_dbg_used_count)
    );

    mem_wb_reg #(
        .DEBUG_TRACE(1)
    ) u_mem_wb_reg (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_alu_result(r_alu_result),
        .i_mem_data  (w_mem_data),
        .i_pc_plus4  (r_pc_plus4),
        .i_rd        (r_rd),
        .i_reg_write (r_reg_write),
        .i_result_src(r_result_src),
        .i_halt      (r_halt),
        .i_illegal   (r_illegal),
        .i_valid     (r_valid),
        .i_instr     (r_instr),
        .o_alu_result(b_alu_result),
        .o_mem_data  (b_mem_data),
        .o_pc_plus4  (b_pc_plus4),
        .o_rd        (b_rd),
        .o_reg_write (b_reg_write),
        .o_result_src(b_result_src),
        .o_halt      (b_halt),
        .o_illegal   (b_illegal),
        .o_valid     (b_valid),
        .o_instr     (b_instr)
    );

    // Segunda instancia con DEBUG_TRACE = 0: solo se mira el campo instr
    mem_wb_reg #(
        .DEBUG_TRACE(0)
    ) u_mem_wb_sin_trace (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_alu_result(r_alu_result),
        .i_mem_data  (w_mem_data),
        .i_pc_plus4  (r_pc_plus4),
        .i_rd        (r_rd),
        .i_reg_write (r_reg_write),
        .i_result_src(r_result_src),
        .i_halt      (r_halt),
        .i_illegal   (r_illegal),
        .i_valid     (r_valid),
        .i_instr     (r_instr),
        .o_alu_result(),
        .o_mem_data  (),
        .o_pc_plus4  (),
        .o_rd        (),
        .o_reg_write (),
        .o_result_src(),
        .o_halt      (),
        .o_illegal   (),
        .o_valid     (),
        .o_instr     (b_instr_sin_trace)
    );

    wb_stage u_wb_stage (
        .i_alu_result     (b_alu_result),
        .i_mem_data       (b_mem_data),
        .i_pc_plus4       (b_pc_plus4),
        .i_rd             (b_rd),
        .i_reg_write      (b_reg_write),
        .i_result_src     (b_result_src),
        .i_halt           (b_halt),
        .i_illegal        (b_illegal),
        .i_valid          (b_valid),
        .o_wb_we          (w_wb_we),
        .o_wb_rd          (w_wb_rd),
        .o_wb_data        (w_wb_data),
        .o_halt_retired   (w_halt_retired),
        .o_illegal_retired(w_illegal_retired)
    );

    always #(PERIODO / 2) clock = ~clock;

    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    // Deja EX/MEM como una instruccion que no hace nada (valid = 1, sin escrituras ni halt).
    task limpiar_control;
        begin
            r_reg_write  = 1'b0;
            r_mem_write  = 1'b0;
            r_result_src = RES_ALU;
            r_halt       = 1'b0;
            r_illegal    = 1'b0;
            r_valid      = 1'b1;
        end
    endtask

    // Store en MEM: un ciclo con mem_write = 1.
    task store;
        input [2:0] funct3;
        input [31:0] addr;
        input [31:0] dato;
        begin
            limpiar_control;
            r_mem_write  = 1'b1;
            r_funct3     = funct3;
            r_alu_result = addr;
            r_store_data = dato;
            r_rd         = 5'd0;
            ciclo;
            r_mem_write = 1'b0;
        end
    endtask

    // Load en MEM y su escritura en WB al ciclo siguiente.
    task load;
        input [255:0] nombre;
        input [2:0] funct3;
        input [31:0] addr;
        input [4:0] rd;
        input [31:0] esperado;
        begin
            limpiar_control;
            r_reg_write  = 1'b1;
            r_result_src = RES_MEM;
            r_funct3     = funct3;
            r_alu_result = addr;
            r_rd         = rd;
            #1 check_eq(nombre, w_mem_data, esperado);  // MEM: combinacional
            ciclo;
            check_eq(nombre, {31'd0, w_wb_we}, 32'd1);  // WB
            check_eq(nombre, {27'd0, w_wb_rd}, {27'd0, rd});
            check_eq(nombre, w_wb_data, esperado);
        end
    endtask

    // Lee una palabra por el puerto de la Debug Unit.
    task ver_palabra;
        input [255:0] nombre;
        input [ADDR_BITS-1:0] palabra;
        input [31:0] esperado;
        input usada;
        begin
            r_dbg_mem_addr = palabra;
            #1;
            check_eq(nombre, w_dbg_mem_data, esperado);
            check_eq(nombre, {31'd0, w_dbg_mem_used}, {31'd0, usada});
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);

        // ---- Arranque como en un LOAD: limpia DMEM y bitmap (reset activo, enable en 0) ----
        r_clear_used  = 1'b1;
        r_dbg_dmem_we = 1'b1;
        for (k = 0; k < DMEM_DEPTH; k = k + 1) begin
            r_dbg_dmem_addr = k[ADDR_BITS-1:0];
            ciclo;
        end
        r_dbg_dmem_we = 1'b0;
        r_clear_used  = 1'b0;
        r_reset       = 1'b0;
        check_eq("reset: MEM/WB vacio", {31'd0, b_valid}, 32'd0);
        check_eq("reset: instr = NOP", b_instr, NOP);
        check_eq("reset: WB no escribe", {31'd0, w_wb_we}, 32'd0);
        check_eq("reset: contador en 0", {23'd0, w_dbg_used_count}, 32'd0);
        ver_palabra("limpieza: palabra 4 en 0", 8'd4, 32'h0000_0000, 1'b0);
        r_enable = 1'b1;

        // ---- Stores ----
        store(F3_W, 32'h0000_0010, 32'h8765_4321);  // sw en la palabra 4
        ver_palabra("sw en 0x10", 8'd4, 32'h8765_4321, 1'b1);
        check_eq("sw: contador = 1", {23'd0, w_dbg_used_count}, 32'd1);
        // AC2: el store llega a WB y no escribe el banco
        check_eq("AC2 sw en WB: no escribe", {31'd0, w_wb_we}, 32'd0);

        // ---- AC1: loads ----
        load("AC1 lw 0x10", F3_W, 32'h0000_0010, 5'd5, 32'h8765_4321);
        load("AC1 lb 0x13 (signo)", F3_B, 32'h0000_0013, 5'd6, 32'hFFFF_FF87);
        load("AC1 lbu 0x13", F3_BU, 32'h0000_0013, 5'd7, 32'h0000_0087);
        load("AC1 lb 0x10", F3_B, 32'h0000_0010, 5'd8, 32'h0000_0021);
        load("AC1 lh 0x12 (signo)", F3_H, 32'h0000_0012, 5'd9, 32'hFFFF_8765);
        load("AC1 lhu 0x12", F3_HU, 32'h0000_0012, 5'd10, 32'h0000_8765);
        load("AC1 lh 0x10", F3_H, 32'h0000_0010, 5'd11, 32'h0000_4321);

        // ---- sb y sh: solo cambian sus bytes ----
        store(F3_B, 32'h0000_0011, 32'h0000_00AB);
        ver_palabra("sb en 0x11", 8'd4, 32'h8765_AB21, 1'b1);
        store(F3_H, 32'h0000_0012, 32'h0000_CDEF);
        ver_palabra("sh en 0x12", 8'd4, 32'hCDEF_AB21, 1'b1);
        check_eq("misma palabra: contador = 1", {23'd0, w_dbg_used_count}, 32'd1);
        load("AC1 lw despues de sb/sh", F3_W, 32'h0000_0010, 5'd12, 32'hCDEF_AB21);

        // ---- AC1: add (ALU) y jal (pc + 4) ----
        limpiar_control;
        r_reg_write  = 1'b1;
        r_result_src = RES_ALU;
        r_alu_result = 32'h0000_1234;
        r_pc_plus4   = 32'h0000_0030;
        r_rd         = 5'd3;
        ciclo;
        check_eq("AC1 add: escribe", {31'd0, w_wb_we}, 32'd1);
        check_eq("AC1 add: rd = x3", {27'd0, w_wb_rd}, 32'd3);
        check_eq("AC1 add: dato de la ALU", w_wb_data, 32'h0000_1234);
        r_result_src = RES_PC4;
        r_rd         = 5'd1;
        ciclo;
        check_eq("AC1 jal: dato = pc + 4", w_wb_data, 32'h0000_0030);
        check_eq("AC1 jal: rd = x1", {27'd0, w_wb_rd}, 32'd1);
        r_result_src = 2'b11;  // no lo genera control_unit: se toma como ALU
        ciclo;
        check_eq("result_src = 11: ALU", w_wb_data, 32'h0000_1234);

        // ---- Burbuja: no escribe memoria ni banco ----
        r_valid      = 1'b0;
        r_reg_write  = 1'b1;
        r_mem_write  = 1'b1;
        r_result_src = RES_ALU;
        r_funct3     = F3_W;
        r_alu_result = 32'h0000_0020;  // palabra 8
        r_store_data = 32'hBAD0_0008;
        ciclo;
        check_eq("burbuja: WB no escribe", {31'd0, w_wb_we}, 32'd0);
        ver_palabra("burbuja: la DMEM no cambia", 8'd8, 32'h0000_0000, 1'b0);

        // ---- Store con i_enable = 0: no escribe; MEM/WB no cambia ----
        limpiar_control;
        r_reg_write  = 1'b1;
        r_alu_result = 32'h0000_5678;
        r_instr      = 32'h0000_0033;
        r_rd         = 5'd4;
        ciclo;
        r_enable        = 1'b0;
        r_antes_wb_data = w_wb_data;
        r_antes_instr   = b_instr;
        r_antes_ctrl    = b_ctrl;
        for (k = 0; k < CICLOS_SIN_ENABLE; k = k + 1) begin
            r_mem_write  = 1'b1;
            r_funct3     = F3_W;
            r_alu_result = 32'h0000_0024;  // palabra 9
            r_store_data = $random(semilla);
            r_reg_write  = $random(semilla);
            r_halt       = $random(semilla);
            r_valid      = $random(semilla);
            r_instr      = $random(semilla);
            ciclo;
            check_eq("enable 0: wb_data", w_wb_data, r_antes_wb_data);
            check_eq("enable 0: instr", b_instr, r_antes_instr);
            check_eq("enable 0: control", {26'd0, b_ctrl}, {26'd0, r_antes_ctrl});
        end
        ver_palabra("enable 0: el store no escribe", 8'd9, 32'h0000_0000, 1'b0);
        r_enable = 1'b1;

        // ---- AC3: HALT e ilegal se retiran exactamente un ciclo ----
        limpiar_control;
        r_instr = NOP;
        ciclo;  // una instruccion cualquiera en WB
        check_eq("AC3 antes del halt: 0", {31'd0, w_halt_retired}, 32'd0);
        r_halt  = 1'b1;
        r_instr = 32'h0000_000B;
        ciclo;  // HALT en WB
        check_eq("AC3 halt en WB: retired", {31'd0, w_halt_retired}, 32'd1);
        check_eq("AC3 halt: no es ilegal", {31'd0, w_illegal_retired}, 32'd0);
        check_eq("AC3 halt: no escribe", {31'd0, w_wb_we}, 32'd0);
        r_halt  = 1'b0;
        r_valid = 1'b0;
        r_instr = NOP;
        ciclo;  // burbuja en WB
        check_eq("AC3 despues del halt: 0", {31'd0, w_halt_retired}, 32'd0);

        limpiar_control;
        r_halt    = 1'b1;
        r_illegal = 1'b1;
        r_instr   = 32'h0000_307F;
        ciclo;
        check_eq("AC3 ilegal en WB: retired", {31'd0, w_halt_retired}, 32'd1);
        check_eq("AC3 ilegal: illegal_retired", {31'd0, w_illegal_retired}, 32'd1);
        r_valid = 1'b0;  // HALT sin valid (no deberia pasar: ID/EX lo anula)
        ciclo;
        check_eq("AC3 halt sin valid: nada", {31'd0, w_halt_retired}, 32'd0);
        check_eq("AC3 ilegal sin valid: nada", {31'd0, w_illegal_retired}, 32'd0);
        r_halt    = 1'b0;
        r_illegal = 1'b0;

        // ---- DEBUG_TRACE = 0: instr vale 0 ----
        limpiar_control;
        r_instr = 32'h0000_0033;
        ciclo;
        check_eq("DEBUG_TRACE=1: instr", b_instr, 32'h0000_0033);
        check_eq("DEBUG_TRACE=0: instr = 0", b_instr_sin_trace, 32'h0000_0000);

        // ---- El reset actua aunque i_enable = 0 ----
        r_enable = 1'b0;
        r_reset  = 1'b1;
        ciclo;
        r_reset = 1'b0;
        check_eq("reset sin enable: valid = 0", {31'd0, b_valid}, 32'd0);
        check_eq("reset sin enable: control en 0", {26'd0, b_ctrl}, 32'd0);
        check_eq("reset sin enable: instr = NOP", b_instr, NOP);
        check_eq("reset sin enable: la DMEM no se borra", u_mem_stage.u_data_mem.r_mem[4],
                 32'hCDEF_AB21);

        tb_finish;
    end
endmodule
