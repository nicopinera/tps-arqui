`timescale 1ns / 1ps

// Testbench de la etapa EX y el latch EX/MEM (US-208, AC1 a AC5).
//
// - El testbench hace de ID/EX: maneja los operandos, el inmediato, funct3/funct7_b5 y las
//   senales de control (tabla_control.md) a mano.
// - AC1: las 10 R, las 9 I aritmeticas (addi con imm negativo: el bit 30 en 1 no la vuelve
//   sub), direccion de load/store y lui. Los valores esperados estan calculados a mano.
// - AC2: beq/bne tomados y no tomados, con destino hacia adelante y hacia atras.
// - AC3: jalr con destino impar; el bit 0 queda en 0.
// - AC4: los 4 valores de fwd_a y fwd_b (11 se toma como 00); store_data, la ALU y el
//   comparador usan el operando forwardeado.
// - AC5: branch tomado y jalr con valid = 0 no redirigen.
// - EX/MEM: carga de todos los campos, burbuja, i_enable = 0, reset sin enable y
//   DEBUG_TRACE = 0.
//
// Los estimulos se cambian en el flanco de bajada; las salidas de EX se miran antes del flanco
// de subida y EX/MEM despues.
module tb_ex_stage;
    `include "tb_utils.vh"

    localparam PERIODO = 10;
    localparam CICLOS_SIN_ENABLE = 30;
    localparam [31:0] NOP = 32'h0000_0013;

    // alu_op (alu_defs.vh) y funct3
    localparam [1:0] OP_ADD = 2'b00;
    localparam [1:0] OP_PASS_B = 2'b01;
    localparam [1:0] OP_R = 2'b10;
    localparam [1:0] OP_I = 2'b11;
    localparam [2:0] F3_BEQ = 3'b000;
    localparam [2:0] F3_BNE = 3'b001;

    // fwd_a / fwd_b
    localparam [1:0] FWD_ID_EX = 2'b00;
    localparam [1:0] FWD_MEM_WB = 2'b01;
    localparam [1:0] FWD_EX_MEM = 2'b10;
    localparam [1:0] FWD_11 = 2'b11;

    // Operandos de AC1: A negativo, para que se note la diferencia entre slt/sltu y srl/sra
    localparam [31:0] A = 32'hF000_000F;
    localparam [31:0] B = 32'h0000_0004;
    localparam [31:0] IMM_M5 = 32'hFFFF_FFFB;  // -5: imm[10] = 1, es decir instr[30] = 1

    reg         clock = 1'b0;
    reg         r_reset = 1'b1;
    reg         r_enable = 1'b0;
    // ID/EX (lo maneja el testbench)
    reg  [31:0] r_pc = 0;
    reg  [31:0] r_rs1_data = 0;
    reg  [31:0] r_rs2_data = 0;
    reg  [31:0] r_imm = 0;
    reg  [ 2:0] r_funct3 = 0;
    reg         r_funct7_b5 = 0;
    reg         r_alu_src = 0;
    reg  [ 1:0] r_alu_op = 0;
    reg         r_branch = 0;
    reg         r_jalr = 0;
    reg         r_valid = 0;
    // Campos que van de ID/EX a EX/MEM sin pasar por EX
    reg  [ 4:0] r_rd = 0;
    reg         r_reg_write = 0;
    reg         r_mem_read = 0;
    reg         r_mem_write = 0;
    reg  [ 1:0] r_result_src = 0;
    reg         r_halt = 0;
    reg         r_illegal = 0;
    reg  [31:0] r_instr = NOP;
    // Forwarding
    reg  [ 1:0] r_fwd_a = FWD_ID_EX;
    reg  [ 1:0] r_fwd_b = FWD_ID_EX;
    reg  [31:0] r_fwd_ex_mem = 0;
    reg  [31:0] r_fwd_mem_wb = 0;

    // EX
    wire [31:0] w_alu_result;
    wire [31:0] w_store_data;
    wire        w_redirect;
    wire [31:0] w_redirect_pc;

    // EX/MEM
    wire [31:0] m_alu_result;
    wire [31:0] m_store_data;
    wire [31:0] m_pc_plus4;
    wire [ 4:0] m_rd;
    wire [ 2:0] m_funct3;
    wire        m_reg_write;
    wire        m_mem_read;
    wire        m_mem_write;
    wire [ 1:0] m_result_src;
    wire        m_halt;
    wire        m_illegal;
    wire        m_valid;
    wire [31:0] m_instr;
    wire [31:0] m_instr_sin_trace;

    // Copia de EX/MEM para el chequeo de enable
    reg  [31:0] r_antes_alu_result;
    reg  [31:0] r_antes_store_data;
    reg  [31:0] r_antes_instr;
    reg  [ 7:0] r_antes_ctrl;

    wire [ 7:0] m_ctrl = {m_reg_write, m_mem_read, m_mem_write, m_result_src, m_halt, m_illegal, m_valid};

    integer     k;
    integer     semilla = 208;

    ex_stage u_ex_stage (
        .i_pc         (r_pc),
        .i_rs1_data   (r_rs1_data),
        .i_rs2_data   (r_rs2_data),
        .i_imm        (r_imm),
        .i_funct3     (r_funct3),
        .i_funct7_b5  (r_funct7_b5),
        .i_alu_src    (r_alu_src),
        .i_alu_op     (r_alu_op),
        .i_branch     (r_branch),
        .i_jalr       (r_jalr),
        .i_valid      (r_valid),
        .i_fwd_a      (r_fwd_a),
        .i_fwd_b      (r_fwd_b),
        .i_fwd_ex_mem (r_fwd_ex_mem),
        .i_fwd_mem_wb (r_fwd_mem_wb),
        .o_alu_result (w_alu_result),
        .o_store_data (w_store_data),
        .o_redirect   (w_redirect),
        .o_redirect_pc(w_redirect_pc)
    );

    ex_mem_reg #(
        .DEBUG_TRACE(1)
    ) u_ex_mem_reg (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_alu_result(w_alu_result),
        .i_store_data(w_store_data),
        .i_pc_plus4  (r_pc + 32'd4),
        .i_rd        (r_rd),
        .i_funct3    (r_funct3),
        .i_reg_write (r_reg_write),
        .i_mem_read  (r_mem_read),
        .i_mem_write (r_mem_write),
        .i_result_src(r_result_src),
        .i_halt      (r_halt),
        .i_illegal   (r_illegal),
        .i_valid     (r_valid),
        .i_instr     (r_instr),
        .o_alu_result(m_alu_result),
        .o_store_data(m_store_data),
        .o_pc_plus4  (m_pc_plus4),
        .o_rd        (m_rd),
        .o_funct3    (m_funct3),
        .o_reg_write (m_reg_write),
        .o_mem_read  (m_mem_read),
        .o_mem_write (m_mem_write),
        .o_result_src(m_result_src),
        .o_halt      (m_halt),
        .o_illegal   (m_illegal),
        .o_valid     (m_valid),
        .o_instr     (m_instr)
    );

    // Segunda instancia con DEBUG_TRACE = 0: solo se mira el campo instr
    ex_mem_reg #(
        .DEBUG_TRACE(0)
    ) u_ex_mem_sin_trace (
        .clock       (clock),
        .i_reset     (r_reset),
        .i_enable    (r_enable),
        .i_alu_result(w_alu_result),
        .i_store_data(w_store_data),
        .i_pc_plus4  (r_pc + 32'd4),
        .i_rd        (r_rd),
        .i_funct3    (r_funct3),
        .i_reg_write (r_reg_write),
        .i_mem_read  (r_mem_read),
        .i_mem_write (r_mem_write),
        .i_result_src(r_result_src),
        .i_halt      (r_halt),
        .i_illegal   (r_illegal),
        .i_valid     (r_valid),
        .i_instr     (r_instr),
        .o_alu_result(),
        .o_store_data(),
        .o_pc_plus4  (),
        .o_rd        (),
        .o_funct3    (),
        .o_reg_write (),
        .o_mem_read  (),
        .o_mem_write (),
        .o_result_src(),
        .o_halt      (),
        .o_illegal   (),
        .o_valid     (),
        .o_instr     (m_instr_sin_trace)
    );

    always #(PERIODO / 2) clock = ~clock;

    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    // Presenta una instruccion de ALU (sin salto) y verifica alu_result.
    task alu_caso;
        input [255:0] nombre;
        input [1:0] alu_op;
        input alu_src;
        input [2:0] funct3;
        input funct7_b5;
        input [31:0] a;
        input [31:0] b;  // rs2 o inmediato, segun alu_src
        input [31:0] esperado;
        begin
            r_alu_op    = alu_op;
            r_alu_src   = alu_src;
            r_funct3    = funct3;
            r_funct7_b5 = funct7_b5;
            r_rs1_data  = a;
            if (alu_src) r_imm = b;
            else r_rs2_data = b;
            r_branch = 1'b0;
            r_jalr   = 1'b0;
            r_valid  = 1'b1;
            #1;
            check_eq(nombre, w_alu_result, esperado);
            check_eq(nombre, {31'd0, w_redirect}, 32'd0);  // sin salto, EX no redirige
        end
    endtask

    // Presenta un branch y verifica la redireccion.
    task branch_caso;
        input [255:0] nombre;
        input [2:0] funct3;
        input [31:0] pc;
        input [31:0] imm;
        input [31:0] a;
        input [31:0] b;
        input valid;
        input tomado;
        begin
            r_alu_op   = OP_ADD;
            r_alu_src  = 1'b0;
            r_funct3   = funct3;
            r_pc       = pc;
            r_imm      = imm;
            r_rs1_data = a;
            r_rs2_data = b;
            r_branch   = 1'b1;
            r_jalr     = 1'b0;
            r_valid    = valid;
            #1;
            check_eq(nombre, {31'd0, w_redirect}, {31'd0, tomado});
            check_eq(nombre, w_redirect_pc, pc + imm);
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);
        r_reset = 1'b0;

        // ---- Reset: EX/MEM vacio ----
        check_eq("reset: valid = 0", {31'd0, m_valid}, 32'd0);
        check_eq("reset: instr = NOP", m_instr, NOP);
        check_eq("reset: control en 0", {24'd0, m_ctrl}, 32'd0);
        r_enable = 1'b1;

        // ---- AC1: R ----
        alu_caso("AC1 add", OP_R, 0, 3'b000, 0, A, B, 32'hF000_0013);
        alu_caso("AC1 sub", OP_R, 0, 3'b000, 1, A, B, 32'hF000_000B);
        alu_caso("AC1 sll", OP_R, 0, 3'b001, 0, A, B, 32'h0000_00F0);
        alu_caso("AC1 slt", OP_R, 0, 3'b010, 0, A, B, 32'h0000_0001);
        alu_caso("AC1 sltu", OP_R, 0, 3'b011, 0, A, B, 32'h0000_0000);
        alu_caso("AC1 xor", OP_R, 0, 3'b100, 0, A, B, 32'hF000_000B);
        alu_caso("AC1 srl", OP_R, 0, 3'b101, 0, A, B, 32'h0F00_0000);
        alu_caso("AC1 sra", OP_R, 0, 3'b101, 1, A, B, 32'hFF00_0000);
        alu_caso("AC1 or", OP_R, 0, 3'b110, 0, A, B, 32'hF000_000F);
        alu_caso("AC1 and", OP_R, 0, 3'b111, 0, A, B, 32'h0000_0004);

        // ---- AC1: I aritmeticas (imm = -5, con instr[30] = 1) ----
        alu_caso("AC1 addi -5 (no es sub)", OP_I, 1, 3'b000, 1, A, IMM_M5, 32'hF000_000A);
        alu_caso("AC1 slti", OP_I, 1, 3'b010, 1, A, IMM_M5, 32'h0000_0001);
        alu_caso("AC1 sltiu", OP_I, 1, 3'b011, 1, A, IMM_M5, 32'h0000_0001);
        alu_caso("AC1 xori", OP_I, 1, 3'b100, 1, A, IMM_M5, 32'h0FFF_FFF4);
        alu_caso("AC1 ori", OP_I, 1, 3'b110, 1, A, IMM_M5, 32'hFFFF_FFFF);
        alu_caso("AC1 andi", OP_I, 1, 3'b111, 1, A, IMM_M5, 32'hF000_000B);
        alu_caso("AC1 slli", OP_I, 1, 3'b001, 0, A, 32'h0000_0004, 32'h0000_00F0);
        alu_caso("AC1 srli", OP_I, 1, 3'b101, 0, A, 32'h0000_0004, 32'h0F00_0000);
        alu_caso("AC1 srai", OP_I, 1, 3'b101, 1, A, 32'h0000_0404, 32'hFF00_0000);

        // ---- AC1: direccion de load y store (alu_op = ADD, funct3 no importa) ----
        alu_caso("AC1 lw: 0x100 - 8", OP_ADD, 1, 3'b010, 1, 32'h0000_0100, 32'hFFFF_FFF8,
                 32'h0000_00F8);
        r_rs2_data = 32'hCAFE_F00D;
        alu_caso("AC1 sw: 0x100 + 12", OP_ADD, 1, 3'b010, 0, 32'h0000_0100, 32'h0000_000C,
                 32'h0000_010C);
        check_eq("AC1 sw: store_data = rs2", w_store_data, 32'hCAFE_F00D);

        // ---- AC1: lui (rs1 basura, la ALU deja pasar el inmediato) ----
        alu_caso("AC1 lui", OP_PASS_B, 1, 3'b110, 0, 32'h1234_5678, 32'hABCD_E000, 32'hABCD_E000);

        // ---- AC2: beq / bne, tomados y no tomados, adelante y atras ----
        branch_caso("AC2 beq igual: tomado +24", F3_BEQ, 32'h40, 32'h0000_0018, 32'h7, 32'h7, 1, 1);
        branch_caso("AC2 beq igual: tomado -36", F3_BEQ, 32'h40, 32'hFFFF_FFDC, 32'h7, 32'h7, 1, 1);
        check_eq("AC2 beq -36: destino 0x1c", w_redirect_pc, 32'h0000_001C);
        branch_caso("AC2 beq distinto: no", F3_BEQ, 32'h40, 32'h0000_0018, 32'h7, 32'h8, 1, 0);
        branch_caso("AC2 beq bit 31: no", F3_BEQ, 32'h40, 32'h0000_0018, 32'h7, 32'h8000_0007, 1,
                    0);
        branch_caso("AC2 bne distinto: tomado", F3_BNE, 32'h40, 32'h0000_0018, 32'h7, 32'h8, 1, 1);
        check_eq("AC2 bne +24: destino 0x58", w_redirect_pc, 32'h0000_0058);
        branch_caso("AC2 bne distinto: tomado -36", F3_BNE, 32'h40, 32'hFFFF_FFDC, 32'h7, 32'h8, 1,
                    1);
        branch_caso("AC2 bne igual: no", F3_BNE, 32'h40, 32'h0000_0018, 32'h7, 32'h7, 1, 0);

        // ---- AC3: jalr limpia el bit 0 del destino ----
        r_branch   = 1'b0;
        r_jalr     = 1'b1;
        r_alu_op   = OP_ADD;
        r_alu_src  = 1'b1;
        r_funct3   = 3'b000;
        r_valid    = 1'b1;
        r_rs1_data = 32'h0000_0101;
        r_imm      = 32'h0000_0000;
        #1;
        check_eq("AC3 jalr 0x101: redirige", {31'd0, w_redirect}, 32'd1);
        check_eq("AC3 jalr 0x101: destino 0x100", w_redirect_pc, 32'h0000_0100);
        r_rs1_data = 32'h0000_0200;
        r_imm      = 32'hFFFF_FFFD;  // -3: 0x1fd
        #1 check_eq("AC3 jalr 0x200-3: destino 0x1fc", w_redirect_pc, 32'h0000_01FC);
        r_imm = 32'h0000_0008;  // par: no cambia
        #1 check_eq("AC3 jalr par: destino 0x208", w_redirect_pc, 32'h0000_0208);

        // ---- AC5: con valid = 0 nunca redirige ----
        r_valid = 1'b0;
        #1 check_eq("AC5 jalr con valid = 0", {31'd0, w_redirect}, 32'd0);
        r_jalr = 1'b0;
        branch_caso("AC5 beq tomado con valid = 0", F3_BEQ, 32'h40, 32'h0000_0018, 32'h7, 32'h7, 0,
                    0);
        branch_caso("AC5 bne tomado con valid = 0", F3_BNE, 32'h40, 32'h0000_0018, 32'h7, 32'h8, 0,
                    0);
        r_branch = 1'b0;
        r_valid  = 1'b1;

        // ---- AC4: forwarding de los dos operandos ----
        r_fwd_ex_mem = 32'h0000_2000;
        r_fwd_mem_wb = 32'h0000_0300;
        r_rs1_data   = 32'h0000_0010;
        r_rs2_data   = 32'h0000_0001;
        // add: A + B con cada selector de A
        r_alu_op     = OP_R;
        r_alu_src    = 1'b0;
        r_funct3     = 3'b000;
        r_funct7_b5  = 1'b0;
        r_fwd_a      = FWD_ID_EX;
        #1 check_eq("AC4 fwd_a = 00: rs1", w_alu_result, 32'h0000_0011);
        r_fwd_a = FWD_MEM_WB;
        #1 check_eq("AC4 fwd_a = 01: MEM/WB", w_alu_result, 32'h0000_0301);
        r_fwd_a = FWD_EX_MEM;
        #1 check_eq("AC4 fwd_a = 10: EX/MEM", w_alu_result, 32'h0000_2001);
        r_fwd_a = FWD_11;
        #1 check_eq("AC4 fwd_a = 11: como 00", w_alu_result, 32'h0000_0011);
        r_fwd_a = FWD_ID_EX;
        // B en la ALU (R) y en store_data
        r_fwd_b = FWD_MEM_WB;
        #1 check_eq("AC4 fwd_b = 01: ALU", w_alu_result, 32'h0000_0310);
        check_eq("AC4 fwd_b = 01: store_data", w_store_data, 32'h0000_0300);
        r_fwd_b = FWD_EX_MEM;
        #1 check_eq("AC4 fwd_b = 10: ALU", w_alu_result, 32'h0000_2010);
        check_eq("AC4 fwd_b = 10: store_data", w_store_data, 32'h0000_2000);
        r_fwd_b = FWD_11;
        #1 check_eq("AC4 fwd_b = 11: store_data = rs2", w_store_data, 32'h0000_0001);
        // Store: la ALU usa el inmediato (alu_src = 1) y store_data el rs2 forwardeado
        r_alu_op  = OP_ADD;
        r_alu_src = 1'b1;
        r_imm     = 32'h0000_0004;
        r_fwd_b   = FWD_EX_MEM;
        #1 check_eq("AC4 sw: direccion con imm", w_alu_result, 32'h0000_0014);
        check_eq("AC4 sw: store_data forwardeado", w_store_data, 32'h0000_2000);
        // jalr con rs1 forwardeado
        r_jalr  = 1'b1;
        r_fwd_a = FWD_MEM_WB;
        r_fwd_b = FWD_ID_EX;
        #1 check_eq("AC4 jalr: destino con rs1 forwardeado", w_redirect_pc, 32'h0000_0304);
        r_jalr  = 1'b0;
        r_fwd_a = FWD_ID_EX;
        // Branch: el comparador usa los operandos forwardeados (rs1 = 0x10, rs2 = 1)
        r_fwd_b = FWD_ID_EX;
        branch_caso("AC4 beq sin forwarding: no", F3_BEQ, 32'h40, 32'h8, 32'h10, 32'h1, 1, 0);
        r_fwd_ex_mem = 32'h0000_0010;
        r_fwd_b      = FWD_EX_MEM;
        branch_caso("AC4 beq con fwd_b = 10: tomado", F3_BEQ, 32'h40, 32'h8, 32'h10, 32'h1, 1, 1);
        r_fwd_a = FWD_MEM_WB;  // A = 0x300, B = 0x10
        branch_caso("AC4 beq con fwd_a = 01: no", F3_BEQ, 32'h40, 32'h8, 32'h10, 32'h1, 1, 0);
        r_fwd_a  = FWD_ID_EX;
        r_fwd_b  = FWD_ID_EX;
        r_branch = 1'b0;

        // ---- EX/MEM: un sw con todos los campos ----
        r_pc         = 32'h0000_0018;
        r_instr      = 32'h0119_2623;  // sw x17, 12(x18)
        r_rd         = 5'd12;
        r_reg_write  = 1'b0;
        r_mem_read   = 1'b0;
        r_mem_write  = 1'b1;
        r_result_src = 2'b00;
        r_halt       = 1'b0;
        r_illegal    = 1'b0;
        r_rs2_data   = 32'hCAFE_F00D;
        alu_caso("sw a EX/MEM", OP_ADD, 1, 3'b010, 0, 32'h0000_0100, 32'h0000_000C, 32'h0000_010C);
        ciclo;
        check_eq("EX/MEM sw: alu_result", m_alu_result, 32'h0000_010C);
        check_eq("EX/MEM sw: store_data", m_store_data, 32'hCAFE_F00D);
        check_eq("EX/MEM sw: pc_plus4", m_pc_plus4, 32'h0000_001C);
        check_eq("EX/MEM sw: rd", {27'd0, m_rd}, 32'd12);
        check_eq("EX/MEM sw: funct3", {29'd0, m_funct3}, 32'd2);
        check_eq("EX/MEM sw: control", {24'd0, m_ctrl}, {24'd0, 8'b0_0_1_00_0_0_1});
        check_eq("EX/MEM sw: instr", m_instr, 32'h0119_2623);

        // Un lw (result_src = MEM) y una ilegal (halt + illegal)
        r_reg_write  = 1'b1;
        r_mem_read   = 1'b1;
        r_mem_write  = 1'b0;
        r_result_src = 2'b01;
        r_instr      = 32'hFF88_2783;  // lw x15, -8(x16)
        ciclo;
        check_eq("EX/MEM lw: control", {24'd0, m_ctrl}, {24'd0, 8'b1_1_0_01_0_0_1});
        r_reg_write  = 1'b0;
        r_mem_read   = 1'b0;
        r_result_src = 2'b00;
        r_halt       = 1'b1;
        r_illegal    = 1'b1;
        r_instr      = 32'h0000_307F;  // ilegal
        ciclo;
        check_eq("EX/MEM ilegal: halt e illegal", {24'd0, m_ctrl}, {24'd0, 8'b0_0_0_00_1_1_1});
        r_halt    = 1'b0;
        r_illegal = 1'b0;

        // Burbuja (valid = 0, control ya en 0 desde ID/EX): se copia tal cual
        r_valid = 1'b0;
        r_instr = NOP;
        ciclo;
        check_eq("EX/MEM burbuja: valid = 0", {31'd0, m_valid}, 32'd0);
        check_eq("EX/MEM burbuja: control en 0", {24'd0, m_ctrl}, 32'd0);
        check_eq("EX/MEM burbuja: instr = NOP", m_instr, NOP);

        // ---- DEBUG_TRACE = 0: instr vale 0 ----
        r_valid = 1'b1;
        r_instr = 32'h0119_2623;
        ciclo;
        check_eq("DEBUG_TRACE=1: instr", m_instr, 32'h0119_2623);
        check_eq("DEBUG_TRACE=0: instr = 0", m_instr_sin_trace, 32'h0000_0000);

        // ---- i_enable = 0: EX/MEM no cambia ----
        r_enable           = 1'b0;
        r_antes_alu_result = m_alu_result;
        r_antes_store_data = m_store_data;
        r_antes_instr      = m_instr;
        r_antes_ctrl       = m_ctrl;
        for (k = 0; k < CICLOS_SIN_ENABLE; k = k + 1) begin
            r_rs1_data  = $random(semilla);
            r_rs2_data  = $random(semilla);
            r_imm       = $random(semilla);
            r_instr     = $random(semilla);
            r_valid     = $random(semilla);
            r_reg_write = $random(semilla);
            r_mem_write = $random(semilla);
            r_halt      = $random(semilla);
            ciclo;
            check_eq("enable 0: alu_result", m_alu_result, r_antes_alu_result);
            check_eq("enable 0: store_data", m_store_data, r_antes_store_data);
            check_eq("enable 0: instr", m_instr, r_antes_instr);
            check_eq("enable 0: control", {24'd0, m_ctrl}, {24'd0, r_antes_ctrl});
        end

        // ---- El reset actua aunque i_enable = 0 ----
        r_reset = 1'b1;
        ciclo;
        r_reset = 1'b0;
        check_eq("reset sin enable: valid = 0", {31'd0, m_valid}, 32'd0);
        check_eq("reset sin enable: control en 0", {24'd0, m_ctrl}, 32'd0);
        check_eq("reset sin enable: alu_result = 0", m_alu_result, 32'h0000_0000);
        check_eq("reset sin enable: instr = NOP", m_instr, NOP);

        tb_finish;
    end
endmodule
