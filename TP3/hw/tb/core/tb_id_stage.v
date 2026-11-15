`timescale 1ns / 1ps

// Testbench de la etapa ID y el latch ID/EX (US-207, AC1 a AC4).
//
// - El testbench hace de IF/ID: maneja pc, instr y valid a mano.
// - El testbench hace de WB: precarga el banco (adentro de id_stage) por i_wb_* con un valor
//   distinto por registro (valor_reg), asi rs1_data y rs2_data dicen que registro se leyo.
// - Las palabras salen del ensamblador del repo (riscv_toolkit), con este programa:
//
//     0x00 atras:    add  x3, x1, x2           0x24  beq  x22, x23, atras
//     0x04           sub  x5, x6, x7           0x28  bne  x24, x25, adelante
//     0x08           sra  x8, x9, x10          0x2c  jal  x1, adelante
//     0x0c           addi x11, x12, -5         0x30  jal  x0, atras
//     0x10           srai x13, x14, 3          0x34  halt
//     0x14           lw   x15, -8(x16)         0x38  .word 0x0000307f   (opcode ilegal)
//     0x18           sw   x17, 12(x18)         0x3c  nop
//     0x1c           lui  x19, 0xABCDE         0x40 adelante: ...
//     0x20           jalr x20, 4(x21)
//
// - Control esperado de tabla_control.md, empaquetado en CTRL_* (13 bits). Las senales "-"
//   de la tabla valen 0 (control_unit emite 0), asi que se verifica el vector entero.
// - Ademas de los AC: banco a traves de la etapa (bypass WB -> ID, puerto de depuracion,
//   escritura con i_enable = 0), flush, bubble, i_enable = 0, reset sin enable y
//   DEBUG_TRACE = 0.
//
// Los estimulos se cambian en el flanco de bajada; las salidas combinacionales de ID se miran
// antes del flanco de subida y ID/EX despues.
module tb_id_stage;
    `include "tb_utils.vh"

    localparam PERIODO = 10;
    localparam CICLOS_SIN_ENABLE = 30;
    localparam [31:0] NOP = 32'h0000_0013;

    // Control: {reg_write, mem_read, mem_write, result_src[1:0], alu_src, alu_op[1:0],
    //           branch, jump, jalr, halt, illegal}
    localparam [12:0] CTRL_R = 13'b1_0_0_00_0_10_0_0_0_0_0;
    localparam [12:0] CTRL_I = 13'b1_0_0_00_1_11_0_0_0_0_0;
    localparam [12:0] CTRL_LOAD = 13'b1_1_0_01_1_00_0_0_0_0_0;
    localparam [12:0] CTRL_STORE = 13'b0_0_1_00_1_00_0_0_0_0_0;
    localparam [12:0] CTRL_LUI = 13'b1_0_0_00_1_01_0_0_0_0_0;
    localparam [12:0] CTRL_JALR = 13'b1_0_0_10_1_00_0_0_1_0_0;
    localparam [12:0] CTRL_BRANCH = 13'b0_0_0_00_0_00_1_0_0_0_0;
    localparam [12:0] CTRL_JAL = 13'b1_0_0_10_0_00_0_1_0_0_0;
    localparam [12:0] CTRL_HALT = 13'b0_0_0_00_0_00_0_0_0_1_0;
    localparam [12:0] CTRL_ILEGAL = 13'b0_0_0_00_0_00_0_0_0_1_1;
    localparam [12:0] CTRL_NADA = 13'b0;

    reg         clock = 1'b0;
    reg         r_reset = 1'b1;
    reg         r_enable = 1'b0;
    reg         r_flush = 1'b0;
    reg         r_bubble = 1'b0;
    // IF/ID (lo maneja el testbench)
    reg  [31:0] r_pc = 0;
    reg  [31:0] r_instr = NOP;
    reg         r_valid = 1'b0;
    // WB (lo maneja el testbench)
    reg         r_we = 1'b0;
    reg  [ 4:0] r_wr_addr = 0;
    reg  [31:0] r_wr_data = 0;
    reg  [ 4:0] r_dbg_addr = 0;

    // ID
    wire [ 4:0] w_rs1;
    wire [ 4:0] w_rs2;
    wire [ 4:0] w_rd;
    wire [ 2:0] w_funct3;
    wire        w_funct7_b5;
    wire [31:0] w_imm;
    wire [31:0] w_rs1_data;
    wire [31:0] w_rs2_data;
    wire        w_reg_write;
    wire        w_mem_read;
    wire        w_mem_write;
    wire [ 1:0] w_result_src;
    wire        w_alu_src;
    wire [ 1:0] w_alu_op;
    wire        w_branch;
    wire        w_jump;
    wire        w_jalr;
    wire        w_halt;
    wire        w_illegal;
    wire        w_uses_rs1;
    wire        w_uses_rs2;
    wire        w_redirect_jal;
    wire [31:0] w_jal_pc;
    wire        w_halt_detected;
    wire [31:0] w_dbg_data;

    // ID/EX
    wire [31:0] e_pc;
    wire [31:0] e_pc_plus4;
    wire [31:0] e_rs1_data;
    wire [31:0] e_rs2_data;
    wire [31:0] e_imm;
    wire [ 4:0] e_rs1;
    wire [ 4:0] e_rs2;
    wire [ 4:0] e_rd;
    wire [ 2:0] e_funct3;
    wire        e_funct7_b5;
    wire        e_reg_write;
    wire        e_mem_read;
    wire        e_mem_write;
    wire [ 1:0] e_result_src;
    wire        e_alu_src;
    wire [ 1:0] e_alu_op;
    wire        e_branch;
    wire        e_jump;
    wire        e_jalr;
    wire        e_halt;
    wire        e_illegal;
    wire        e_valid;
    wire [31:0] e_instr;
    wire [31:0] e_instr_sin_trace;

    wire [12:0] e_ctrl = {
        e_reg_write,
        e_mem_read,
        e_mem_write,
        e_result_src,
        e_alu_src,
        e_alu_op,
        e_branch,
        e_jump,
        e_jalr,
        e_halt,
        e_illegal
    };

    // Copia de ID/EX para el AC de enable
    reg  [31:0] r_antes_pc;
    reg  [31:0] r_antes_imm;
    reg  [12:0] r_antes_ctrl;
    reg         r_antes_valid;
    reg  [31:0] r_antes_instr;

    integer     k;
    integer     semilla = 207;

    id_stage u_id_stage (
        .clock          (clock),
        .i_enable       (r_enable),
        .i_clear        (r_reset),
        .i_pc           (r_pc),
        .i_instr        (r_instr),
        .i_valid        (r_valid),
        .i_wb_we        (r_we),
        .i_wb_rd        (r_wr_addr),
        .i_wb_data      (r_wr_data),
        .i_dbg_reg_addr (r_dbg_addr),
        .o_dbg_reg_data (w_dbg_data),
        .o_rs1_data     (w_rs1_data),
        .o_rs2_data     (w_rs2_data),
        .o_rs1          (w_rs1),
        .o_rs2          (w_rs2),
        .o_rd           (w_rd),
        .o_funct3       (w_funct3),
        .o_funct7_b5    (w_funct7_b5),
        .o_imm          (w_imm),
        .o_reg_write    (w_reg_write),
        .o_mem_read     (w_mem_read),
        .o_mem_write    (w_mem_write),
        .o_result_src   (w_result_src),
        .o_alu_src      (w_alu_src),
        .o_alu_op       (w_alu_op),
        .o_branch       (w_branch),
        .o_jump         (w_jump),
        .o_jalr         (w_jalr),
        .o_halt         (w_halt),
        .o_illegal      (w_illegal),
        .o_uses_rs1     (w_uses_rs1),
        .o_uses_rs2     (w_uses_rs2),
        .o_redirect_jal (w_redirect_jal),
        .o_jal_pc       (w_jal_pc),
        .o_halt_detected(w_halt_detected)
    );

    id_ex_reg #(
        .DEBUG_TRACE(1)
    ) u_id_ex_reg (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_flush     (r_flush),
        .i_bubble    (r_bubble),
        .i_pc        (r_pc),
        .i_pc_plus4  (r_pc + 32'd4),
        .i_rs1_data  (w_rs1_data),
        .i_rs2_data  (w_rs2_data),
        .i_imm       (w_imm),
        .i_rs1       (w_rs1),
        .i_rs2       (w_rs2),
        .i_rd        (w_rd),
        .i_funct3    (w_funct3),
        .i_funct7_b5 (w_funct7_b5),
        .i_reg_write (w_reg_write),
        .i_mem_read  (w_mem_read),
        .i_mem_write (w_mem_write),
        .i_result_src(w_result_src),
        .i_alu_src   (w_alu_src),
        .i_alu_op    (w_alu_op),
        .i_branch    (w_branch),
        .i_jump      (w_jump),
        .i_jalr      (w_jalr),
        .i_halt      (w_halt),
        .i_illegal   (w_illegal),
        .i_valid     (r_valid),
        .i_instr     (r_instr),
        .o_pc        (e_pc),
        .o_pc_plus4  (e_pc_plus4),
        .o_rs1_data  (e_rs1_data),
        .o_rs2_data  (e_rs2_data),
        .o_imm       (e_imm),
        .o_rs1       (e_rs1),
        .o_rs2       (e_rs2),
        .o_rd        (e_rd),
        .o_funct3    (e_funct3),
        .o_funct7_b5 (e_funct7_b5),
        .o_reg_write (e_reg_write),
        .o_mem_read  (e_mem_read),
        .o_mem_write (e_mem_write),
        .o_result_src(e_result_src),
        .o_alu_src   (e_alu_src),
        .o_alu_op    (e_alu_op),
        .o_branch    (e_branch),
        .o_jump      (e_jump),
        .o_jalr      (e_jalr),
        .o_halt      (e_halt),
        .o_illegal   (e_illegal),
        .o_valid     (e_valid),
        .o_instr     (e_instr)
    );

    // Segunda instancia con DEBUG_TRACE = 0: solo se mira el campo instr (las demas salidas
    // quedan sin conectar a proposito).
    id_ex_reg #(
        .DEBUG_TRACE(0)
    ) u_id_ex_sin_trace (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_flush     (r_flush),
        .i_bubble    (r_bubble),
        .i_pc        (r_pc),
        .i_pc_plus4  (r_pc + 32'd4),
        .i_rs1_data  (w_rs1_data),
        .i_rs2_data  (w_rs2_data),
        .i_imm       (w_imm),
        .i_rs1       (w_rs1),
        .i_rs2       (w_rs2),
        .i_rd        (w_rd),
        .i_funct3    (w_funct3),
        .i_funct7_b5 (w_funct7_b5),
        .i_reg_write (w_reg_write),
        .i_mem_read  (w_mem_read),
        .i_mem_write (w_mem_write),
        .i_result_src(w_result_src),
        .i_alu_src   (w_alu_src),
        .i_alu_op    (w_alu_op),
        .i_branch    (w_branch),
        .i_jump      (w_jump),
        .i_jalr      (w_jalr),
        .i_halt      (w_halt),
        .i_illegal   (w_illegal),
        .i_valid     (r_valid),
        .i_instr     (r_instr),
        .o_pc        (),
        .o_pc_plus4  (),
        .o_rs1_data  (),
        .o_rs2_data  (),
        .o_imm       (),
        .o_rs1       (),
        .o_rs2       (),
        .o_rd        (),
        .o_funct3    (),
        .o_funct7_b5 (),
        .o_reg_write (),
        .o_mem_read  (),
        .o_mem_write (),
        .o_result_src(),
        .o_alu_src   (),
        .o_alu_op    (),
        .o_branch    (),
        .o_jump      (),
        .o_jalr      (),
        .o_halt      (),
        .o_illegal   (),
        .o_valid     (),
        .o_instr     (e_instr_sin_trace)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Valor precargado en el registro n (x0 vale 0 siempre)
    function [31:0] valor_reg;
        input [4:0] n;
        begin
            valor_reg = (n == 5'd0) ? 32'h0000_0000 : {8'hA0, 3'b000, n, 8'h5C, 3'b000, n};
        end
    endfunction

    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    // Presenta una instruccion en "IF/ID", con valid = 1, y la pasa a ID/EX.
    task decodificar;
        input [31:0] pc;
        input [31:0] instr;
        begin
            r_pc    = pc;
            r_instr = instr;
            r_valid = 1'b1;
            ciclo;
        end
    endtask

    // AC1: verifica el contenido de ID/EX despues del flanco.
    task ver_id_ex;
        input [255:0] nombre;
        input [31:0] pc;
        input [31:0] instr;
        input [4:0] rs1;
        input [4:0] rs2;
        input [4:0] rd;
        input [2:0] funct3;
        input funct7_b5;
        input [31:0] imm;
        input ver_imm;  // 0 = imm "-" en la tabla (R, halt)
        input [12:0] ctrl;
        begin
            check_eq(nombre, e_pc, pc);
            check_eq(nombre, e_pc_plus4, pc + 4);
            check_eq(nombre, e_instr, instr);
            check_eq(nombre, {31'd0, e_valid}, 32'd1);
            check_eq(nombre, {27'd0, e_rs1}, {27'd0, rs1});
            check_eq(nombre, {27'd0, e_rs2}, {27'd0, rs2});
            check_eq(nombre, {27'd0, e_rd}, {27'd0, rd});
            check_eq(nombre, {29'd0, e_funct3}, {29'd0, funct3});
            check_eq(nombre, {31'd0, e_funct7_b5}, {31'd0, funct7_b5});
            check_eq(nombre, e_rs1_data, valor_reg(rs1));
            check_eq(nombre, e_rs2_data, valor_reg(rs2));
            if (ver_imm) check_eq(nombre, e_imm, imm);
            check_eq(nombre, {19'd0, e_ctrl}, {19'd0, ctrl});
        end
    endtask

    // Verifica una burbuja en ID/EX: valid = 0, instr = NOP y control en 0.
    task ver_burbuja;
        input [255:0] nombre;
        begin
            check_eq(nombre, {31'd0, e_valid}, 32'd0);
            check_eq(nombre, e_instr, NOP);
            check_eq(nombre, {19'd0, e_ctrl}, {19'd0, CTRL_NADA});
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);

        // ---- Precarga del banco (x1..x31), por el puerto de WB ----
        r_reset  = 1'b0;
        r_enable = 1'b1;
        r_we     = 1'b1;
        for (k = 1; k < 32; k = k + 1) begin
            r_wr_addr = k[4:0];
            r_wr_data = valor_reg(k[4:0]);
            ciclo;
        end
        r_we       = 1'b0;
        r_dbg_addr = 5'd5;
        #1 check_eq("banco: dbg lee x5", w_dbg_data, valor_reg(5'd5));

        // ---- Reset: ID/EX vacio ----
        r_reset = 1'b1;
        ciclo;
        r_reset = 1'b0;
        ver_burbuja("reset: ID/EX vacio");
        check_eq("reset: el banco tambien se borra", w_dbg_data, 32'h0000_0000);
        // El reset tambien limpia el banco (i_clear): se vuelve a cargar
        r_we = 1'b1;
        for (k = 1; k < 32; k = k + 1) begin
            r_wr_addr = k[4:0];
            r_wr_data = valor_reg(k[4:0]);
            ciclo;
        end
        r_we = 1'b0;

        // ---- AC1: cada tipo de instruccion llega a ID/EX con sus operandos y senales ----
        decodificar(32'h00, 32'h002081b3);  // add x3, x1, x2
        ver_id_ex("AC1 add", 32'h00, 32'h002081b3, 5'd1, 5'd2, 5'd3, 3'b000, 1'b0, 0, 0, CTRL_R);

        decodificar(32'h04, 32'h407302b3);  // sub x5, x6, x7
        ver_id_ex("AC1 sub", 32'h04, 32'h407302b3, 5'd6, 5'd7, 5'd5, 3'b000, 1'b1, 0, 0, CTRL_R);

        decodificar(32'h08, 32'h40a4d433);  // sra x8, x9, x10
        ver_id_ex("AC1 sra", 32'h08, 32'h40a4d433, 5'd9, 5'd10, 5'd8, 3'b101, 1'b1, 0, 0, CTRL_R);

        decodificar(32'h0c, 32'hffb60593);  // addi x11, x12, -5
        ver_id_ex("AC1 addi", 32'h0c, 32'hffb60593, 5'd12, 5'd27, 5'd11, 3'b000, 1'b1, 32'hFFFF_FFFB, 1,
                  CTRL_I);

        decodificar(32'h10, 32'h40375693);  // srai x13, x14, 3
        ver_id_ex("AC1 srai", 32'h10, 32'h40375693, 5'd14, 5'd3, 5'd13, 3'b101, 1'b1, 32'h0000_0403, 1,
                  CTRL_I);

        decodificar(32'h14, 32'hff882783);  // lw x15, -8(x16)
        ver_id_ex("AC1 lw", 32'h14, 32'hff882783, 5'd16, 5'd24, 5'd15, 3'b010, 1'b1, 32'hFFFF_FFF8, 1,
                  CTRL_LOAD);

        decodificar(32'h18, 32'h01192623);  // sw x17, 12(x18)
        ver_id_ex("AC1 sw", 32'h18, 32'h01192623, 5'd18, 5'd17, 5'd12, 3'b010, 1'b0, 32'h0000_000C, 1,
                  CTRL_STORE);

        decodificar(32'h1c, 32'habcde9b7);  // lui x19, 0xABCDE
        ver_id_ex("AC1 lui", 32'h1c, 32'habcde9b7, 5'd27, 5'd28, 5'd19, 3'b110, 1'b0, 32'hABCD_E000, 1,
                  CTRL_LUI);

        decodificar(32'h20, 32'h004a8a67);  // jalr x20, 4(x21)
        ver_id_ex("AC1 jalr", 32'h20, 32'h004a8a67, 5'd21, 5'd4, 5'd20, 3'b000, 1'b0, 32'h0000_0004, 1,
                  CTRL_JALR);

        decodificar(32'h24, 32'hfd7b0ee3);  // beq x22, x23, atras (-36)
        ver_id_ex("AC1 beq", 32'h24, 32'hfd7b0ee3, 5'd22, 5'd23, 5'd29, 3'b000, 1'b1, 32'hFFFF_FFDC, 1,
                  CTRL_BRANCH);

        decodificar(32'h28, 32'h019c1c63);  // bne x24, x25, adelante (+24)
        ver_id_ex("AC1 bne", 32'h28, 32'h019c1c63, 5'd24, 5'd25, 5'd24, 3'b001, 1'b0, 32'h0000_0018, 1,
                  CTRL_BRANCH);

        // ---- AC4: jal redirige en el mismo ciclo, con offset positivo y negativo ----
        r_pc    = 32'h2c;
        r_instr = 32'h014000ef;  // jal x1, adelante (+20)
        r_valid = 1'b1;
        #1;
        check_eq("AC4 jal +: redirect", {31'd0, w_redirect_jal}, 32'd1);
        check_eq("AC4 jal +: destino 0x40", w_jal_pc, 32'h0000_0040);
        ciclo;
        ver_id_ex("AC1 jal +", 32'h2c, 32'h014000ef, 5'd0, 5'd20, 5'd1, 3'b000, 1'b0, 32'h0000_0014, 1,
                  CTRL_JAL);

        r_pc    = 32'h30;
        r_instr = 32'hfd1ff06f;  // jal x0, atras (-48)
        #1;
        check_eq("AC4 jal -: redirect", {31'd0, w_redirect_jal}, 32'd1);
        check_eq("AC4 jal -: destino 0x00", w_jal_pc, 32'h0000_0000);
        ciclo;
        ver_id_ex("AC1 jal -", 32'h30, 32'hfd1ff06f, 5'd31, 5'd17, 5'd0, 3'b111, 1'b1, 32'hFFFF_FFD0, 1,
                  CTRL_JAL);

        // Solo jal redirige desde ID: ni jalr ni un branch
        r_pc    = 32'h20;
        r_instr = 32'h004a8a67;  // jalr
        #1 check_eq("jalr no redirige en ID", {31'd0, w_redirect_jal}, 32'd0);
        r_instr = 32'hfd7b0ee3;  // beq
        #1 check_eq("beq no redirige en ID", {31'd0, w_redirect_jal}, 32'd0);

        // ---- AC3: HALT e ilegal activan o_halt_detected (solo con valid) ----
        r_pc    = 32'h34;
        r_instr = 32'h0000000b;  // halt
        #1 check_eq("AC3 halt detectado", {31'd0, w_halt_detected}, 32'd1);
        ciclo;
        check_eq("AC3 halt en ID/EX", {19'd0, e_ctrl}, {19'd0, CTRL_HALT});
        check_eq("AC3 halt valido", {31'd0, e_valid}, 32'd1);

        r_pc    = 32'h38;
        r_instr = 32'h0000307f;  // opcode 1111111: ilegal
        #1 check_eq("AC3 ilegal detectada", {31'd0, w_halt_detected}, 32'd1);
        ciclo;
        check_eq("AC3 ilegal: illegal = 1", {19'd0, e_ctrl}, {19'd0, CTRL_ILEGAL});

        r_instr = 32'h02208133;  // mul x2, x1, x2 (extension M): funct7 ilegal
        #1 check_eq("AC3 mul es ilegal", {31'd0, w_halt_detected}, 32'd1);
        ciclo;
        check_eq("AC3 mul: illegal = 1", {19'd0, e_ctrl}, {19'd0, CTRL_ILEGAL});

        r_instr = 32'h00003003;  // load con funct3 = 011 (ld, RV64): ilegal
        #1 check_eq("AC3 ld es ilegal", {31'd0, w_halt_detected}, 32'd1);

        r_instr = 32'h002081b3;  // add: no es HALT
        #1 check_eq("AC3 add no es halt", {31'd0, w_halt_detected}, 32'd0);

        // ---- AC2: con valid = 0 en IF/ID, ID/EX recibe una burbuja ----
        r_valid = 1'b0;
        r_instr = 32'h0000000b;  // halt sin valid
        #1 check_eq("AC3 halt sin valid: nada", {31'd0, w_halt_detected}, 32'd0);
        r_instr = 32'h014000ef;  // jal sin valid
        #1 check_eq("AC2 jal sin valid: no redirige", {31'd0, w_redirect_jal}, 32'd0);
        r_pc    = 32'h00;
        r_instr = 32'h002081b3;  // add sin valid
        ciclo;
        ver_burbuja("AC2 valid = 0 -> burbuja");
        check_eq("AC2 los datos se cargan igual", e_pc, 32'h0000_0000);
        check_eq("AC2 rd se carga igual", {27'd0, e_rd}, 32'd3);

        // ---- Flush (redireccion de EX) y bubble (load-use/ABORT): burbuja ----
        r_flush = 1'b1;
        decodificar(32'h14, 32'hff882783);  // lw
        ver_burbuja("flush -> burbuja");
        r_flush = 1'b0;
        decodificar(32'h14, 32'hff882783);
        ver_id_ex("despues del flush", 32'h14, 32'hff882783, 5'd16, 5'd24, 5'd15, 3'b010, 1'b1,
                  32'hFFFF_FFF8, 1, CTRL_LOAD);

        r_bubble = 1'b1;
        decodificar(32'h34, 32'h0000000b);  // un halt con bubble no llega a EX como halt
        ver_burbuja("bubble -> burbuja (halt anulado)");
        r_bubble = 1'b0;

        // ---- DEBUG_TRACE = 0: instr vale 0, con instruccion o con burbuja ----
        decodificar(32'h00, 32'h002081b3);
        check_eq("DEBUG_TRACE=1: instr", e_instr, 32'h002081b3);
        check_eq("DEBUG_TRACE=0: instr = 0", e_instr_sin_trace, 32'h0000_0000);
        r_flush = 1'b1;
        ciclo;
        r_flush = 1'b0;
        check_eq("DEBUG_TRACE=0: burbuja = 0", e_instr_sin_trace, 32'h0000_0000);

        // ---- Banco a traves de la etapa ----
        // Bypass WB -> ID: sub x5, x6, x7 mientras WB escribe x6; ID/EX recibe el valor nuevo
        r_we      = 1'b1;
        r_wr_addr = 5'd6;
        r_wr_data = 32'hDEAD_BEEF;
        decodificar(32'h04, 32'h407302b3);
        check_eq("banco: bypass WB -> ID (rs1)", e_rs1_data, 32'hDEAD_BEEF);
        check_eq("banco: rs2 sin bypass", e_rs2_data, valor_reg(5'd7));
        r_dbg_addr = 5'd6;
        #1 check_eq("banco: x6 quedo escrito", w_dbg_data, 32'hDEAD_BEEF);
        // Bypass en rs2 (vuelve x6 a su valor): sub x5, x7, x6
        r_wr_data = valor_reg(5'd6);
        decodificar(32'h04, 32'h406382b3);
        check_eq("banco: bypass WB -> ID (rs2)", e_rs2_data, valor_reg(5'd6));
        // WB escribe x0: no queda escrito ni hace bypass (add x3, x0, x0)
        r_wr_addr = 5'd0;
        r_wr_data = 32'hFFFF_FFFF;
        decodificar(32'h00, 32'h000001b3);
        check_eq("banco: x0 no hace bypass", e_rs1_data, 32'h0000_0000);
        r_dbg_addr = 5'd0;
        #1 check_eq("banco: x0 sigue en 0", w_dbg_data, 32'h0000_0000);
        // Con i_enable = 0, WB no escribe
        r_enable  = 1'b0;
        r_wr_addr = 5'd9;
        r_wr_data = 32'h1234_5678;
        ciclo;
        r_dbg_addr = 5'd9;
        #1 check_eq("banco: sin enable no escribe", w_dbg_data, valor_reg(5'd9));
        r_we     = 1'b0;
        r_enable = 1'b1;

        // ---- i_enable = 0: ID/EX no cambia ----
        decodificar(32'h1c, 32'habcde9b7);  // lui
        r_enable      = 1'b0;
        r_antes_pc    = e_pc;
        r_antes_imm   = e_imm;
        r_antes_ctrl  = e_ctrl;
        r_antes_valid = e_valid;
        r_antes_instr = e_instr;
        for (k = 0; k < CICLOS_SIN_ENABLE; k = k + 1) begin
            r_pc     = {$random(semilla)} & 32'h0000_03FC;
            r_instr  = $random(semilla);
            r_valid  = $random(semilla);
            r_flush  = $random(semilla);
            r_bubble = $random(semilla);
            ciclo;
            check_eq("enable 0: pc", e_pc, r_antes_pc);
            check_eq("enable 0: imm", e_imm, r_antes_imm);
            check_eq("enable 0: ctrl", {19'd0, e_ctrl}, {19'd0, r_antes_ctrl});
            check_eq("enable 0: valid", {31'd0, e_valid}, {31'd0, r_antes_valid});
            check_eq("enable 0: instr", e_instr, r_antes_instr);
        end
        r_flush  = 1'b0;
        r_bubble = 1'b0;

        // ---- El reset actua aunque i_enable = 0 ----
        r_reset = 1'b1;
        ciclo;
        r_reset = 1'b0;
        ver_burbuja("reset sin enable");
        check_eq("reset sin enable: pc = 0", e_pc, 32'h0000_0000);

        tb_finish;
    end
endmodule
