`timescale 1ns / 1ps

// Testbench de la unidad de control.
//
// Parte 1 (AC1, AC5): una fila por instruccion, copiada de docs/interfaces/tabla_control.md
//   seccion 2. Las palabras salen del ensamblador del proyecto. Donde la tabla dice "-" se pasa
//   X y esa senal no se verifica.
// Parte 2 (AC3): palabras con opcode custom-0 -> HALT, no ilegal.
// Parte 3 (AC4): palabras ilegales de la seccion 3 de la tabla.
// Parte 4: barrido de los 128 opcodes (funct3 = funct7 = 0): solo los 9 de la tabla son legales.
module tb_control_unit;
    `include "tb_utils.vh"
    `include "alu_defs.vh"
    `include "control_defs.vh"

    reg     [ 31:0] r_instr;

    wire            w_reg_write;
    wire            w_mem_read;
    wire            w_mem_write;
    wire    [  1:0] w_result_src;
    wire            w_alu_src;
    wire    [  1:0] w_alu_op;
    wire            w_branch;
    wire            w_jump;
    wire            w_jalr;
    wire    [  2:0] w_imm_type;
    wire            w_halt;
    wire            w_illegal;
    wire            w_uses_rs1;
    wire            w_uses_rs2;

    reg     [255:0] r_actual;  // instruccion que se esta probando (para el mensaje de falla)
    integer         op;

    control_unit u_control_unit (
        .i_opcode    (r_instr[6:0]),
        .i_funct3    (r_instr[14:12]),
        .i_funct7    (r_instr[31:25]),
        .o_reg_write (w_reg_write),
        .o_mem_read  (w_mem_read),
        .o_mem_write (w_mem_write),
        .o_result_src(w_result_src),
        .o_alu_src   (w_alu_src),
        .o_alu_op    (w_alu_op),
        .o_branch    (w_branch),
        .o_jump      (w_jump),
        .o_jalr      (w_jalr),
        .o_imm_type  (w_imm_type),
        .o_halt      (w_halt),
        .o_illegal   (w_illegal),
        .o_uses_rs1  (w_uses_rs1),
        .o_uses_rs2  (w_uses_rs2)
    );

    // Compara una señal; si el esperado tiene X ("-" en la tabla) no la verifica.
    task ver;
        input [255:0] senal;
        input [2:0] obtenido;
        input [2:0] esperado;
        begin
            if (^esperado !== 1'bx) begin
                if (obtenido !== esperado) $display("  en: %0s", r_actual);
                check_eq(senal, {29'd0, obtenido}, {29'd0, esperado});
            end
        end
    endtask

    // Una fila de la tabla: misma columna y mismo orden que tabla_control.md.
    task fila;
        input [255:0] nombre;
        input [31:0] instr;
        input reg_write, mem_read, mem_write;
        input [1:0] result_src;
        input alu_src;
        input [1:0] alu_op;
        input branch, jump, jalr;
        input [2:0] imm_type;
        input halt, illegal, uses_rs1, uses_rs2;
        begin
            r_actual = nombre;
            r_instr  = instr;
            #1;
            ver("reg_write", {2'b0, w_reg_write}, {2'b0, reg_write});
            ver("mem_read", {2'b0, w_mem_read}, {2'b0, mem_read});
            ver("mem_write", {2'b0, w_mem_write}, {2'b0, mem_write});
            ver("result_src", {1'b0, w_result_src}, {1'b0, result_src});
            ver("alu_src", {2'b0, w_alu_src}, {2'b0, alu_src});
            ver("alu_op", {1'b0, w_alu_op}, {1'b0, alu_op});
            ver("branch", {2'b0, w_branch}, {2'b0, branch});
            ver("jump", {2'b0, w_jump}, {2'b0, jump});
            ver("jalr", {2'b0, w_jalr}, {2'b0, jalr});
            ver("imm_type", w_imm_type, imm_type);
            ver("halt", {2'b0, w_halt}, {2'b0, halt});
            ver("illegal", {2'b0, w_illegal}, {2'b0, illegal});
            ver("uses_rs1", {2'b0, w_uses_rs1}, {2'b0, uses_rs1});
            ver("uses_rs2", {2'b0, w_uses_rs2}, {2'b0, uses_rs2});
        end
    endtask

    // HALT (AC3): halt = 1, illegal = 0, sin escrituras ni lecturas.
    task es_halt;
        input [255:0] nombre;
        input [31:0] instr;
        begin
            fila(nombre, instr, 0, 0, 0, 2'bxx, 1'bx, 2'bxx, 0, 0, 0, 3'bxxx, 1, 0, 0, 0);
        end
    endtask

    // Ilegal (AC4): halt = 1, illegal = 1, sin escrituras ni lecturas.
    task es_ilegal;
        input [255:0] nombre;
        input [31:0] instr;
        begin
            fila(nombre, instr, 0, 0, 0, 2'bxx, 1'bx, 2'bxx, 0, 0, 0, 3'bxxx, 1, 1, 0, 0);
        end
    endtask

    localparam X1 = 1'bx;
    localparam [1:0] X2 = 2'bxx;
    localparam [2:0] X3 = 3'bxxx;

    initial begin
        tb_init;

        // ---- Parte 1: las 33 instrucciones (tabla_control.md, seccion 2) ----
        //   nombre                   palabra        rw mr mw res      as  alu_op         br j  jr imm    h  il u1 u2
        fila("add x1, x2, x3", 32'h003100b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("sub x1, x2, x3", 32'h403100b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("sll x1, x2, x3", 32'h003110b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("slt x1, x2, x3", 32'h003120b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("sltu x1, x2, x3", 32'h003130b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("xor x1, x2, x3", 32'h003140b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("srl x1, x2, x3", 32'h003150b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("sra x1, x2, x3", 32'h403150b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("or x1, x2, x3", 32'h003160b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        fila("and x1, x2, x3", 32'h003170b3, 1, 0, 0, RES_ALU, 0, ALU_OP_R, 0, 0, 0, X3, 0, 0, 1, 1);
        // addi con el bit 30 en 1 (inmediato -1024): tiene que seguir siendo legal.
        fila("addi x1, x2, -1024", 32'hc0010093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("slti x1, x2, 5", 32'h00512093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("sltiu x1, x2, -1", 32'hfff13093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("xori x1, x2, 255", 32'h0ff14093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("ori x1, x2, 1", 32'h00116093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("andi x1, x2, -2048", 32'h80017093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("slli x1, x2, 31", 32'h01f11093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("srli x1, x2, 7", 32'h00715093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("srai x1, x2, 31", 32'h41f15093, 1, 0, 0, RES_ALU, 1, ALU_OP_I, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("lb x1, -4(x2)", 32'hffc10083, 1, 1, 0, RES_MEM, 1, ALU_OP_ADD, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("lh x1, 2(x2)", 32'h00211083, 1, 1, 0, RES_MEM, 1, ALU_OP_ADD, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("lw x1, 8(x2)", 32'h00812083, 1, 1, 0, RES_MEM, 1, ALU_OP_ADD, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("lbu x1, 1(x2)", 32'h00114083, 1, 1, 0, RES_MEM, 1, ALU_OP_ADD, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("lhu x1, 6(x2)", 32'h00615083, 1, 1, 0, RES_MEM, 1, ALU_OP_ADD, 0, 0, 0, IMM_I, 0, 0, 1, 0);
        fila("jalr x1, 12(x2)", 32'h00c100e7, 1, 0, 0, RES_PC4, 1, ALU_OP_ADD, 0, 0, 1, IMM_I, 0, 0, 1, 0);
        fila("sb x3, -1(x2)", 32'hfe310fa3, 0, 0, 1, X2, 1, ALU_OP_ADD, 0, 0, 0, IMM_S, 0, 0, 1, 1);
        fila("sh x3, 2(x2)", 32'h00311123, 0, 0, 1, X2, 1, ALU_OP_ADD, 0, 0, 0, IMM_S, 0, 0, 1, 1);
        fila("sw x3, 2044(x2)", 32'h7e312e23, 0, 0, 1, X2, 1, ALU_OP_ADD, 0, 0, 0, IMM_S, 0, 0, 1, 1);
        fila("beq x2, x3, inicio", 32'hf83108e3, 0, 0, 0, X2, X1, X2, 1, 0, 0, IMM_B, 0, 0, 1, 1);
        fila("bne x2, x3, inicio", 32'hf83116e3, 0, 0, 0, X2, X1, X2, 1, 0, 0, IMM_B, 0, 0, 1, 1);
        fila("lui x1, 0xFFFFF", 32'hfffff0b7, 1, 0, 0, RES_ALU, 1, ALU_OP_PASS_B, 0, 0, 0, IMM_U, 0, 0, 0, 0);
        fila("jal x1, inicio", 32'hf85ff0ef, 1, 0, 0, RES_PC4, X1, X2, 0, 1, 0, IMM_J, 0, 0, 0, 0);
        fila("halt", 32'h0000000b, 0, 0, 0, X2, X1, X2, 0, 0, 0, X3, 1, 0, 0, 0);

        // ---- Parte 2 (AC3): cualquier palabra con opcode custom-0 es HALT ----
        es_halt("AC3 custom-0 0xFFFFFF8B", 32'hFFFF_FF8B);
        es_halt("AC3 custom-0 0x1234508B", 32'h1234_508B);
        es_halt("AC3 custom-0 0x0000700B", 32'h0000_700B);

        // ---- Parte 3 (AC4): ilegales (tabla_control.md, seccion 3) ----
        es_ilegal("AC4 0x00000000", 32'h0000_0000);
        es_ilegal("AC4 0xFFFFFFFF", 32'hFFFF_FFFF);
        es_ilegal("AC4 branch funct3=010", 32'hf83128e3);
        es_ilegal("blt (funct3=100)", 32'hf83148e3);
        es_ilegal("bge (funct3=101)", 32'hf83158e3);
        es_ilegal("bltu (funct3=110)", 32'hf83168e3);
        es_ilegal("bgeu (funct3=111)", 32'hf83178e3);
        es_ilegal("load funct3=011 (ld)", 32'h00813083);
        es_ilegal("load funct3=110 (lwu)", 32'h00816083);
        es_ilegal("load funct3=111", 32'h00817083);
        es_ilegal("store funct3=011 (sd)", 32'h7e313e23);
        es_ilegal("store funct3=100", 32'h7e314e23);
        es_ilegal("store funct3=111", 32'h7e317e23);
        es_ilegal("slli funct7=0000001", 32'h03f11093);
        es_ilegal("slli funct7=0100000", 32'h41f11093);
        es_ilegal("srli funct7=0000001", 32'h02715093);
        es_ilegal("mul (R funct7=0000001)", 32'h023100b3);
        es_ilegal("R funct7=0100000 funct3=001", 32'h403110b3);
        es_ilegal("R funct7=0100000 funct3=100", 32'h403140b3);
        es_ilegal("jalr funct3=001", 32'h00c110e7);
        es_ilegal("auipc", 32'h0000_0097);
        es_ilegal("ecall", 32'h0000_0073);
        es_ilegal("ebreak", 32'h0010_0073);
        es_ilegal("fence", 32'h0000_000f);

        // ---- Parte 4: barrido de opcodes con funct3 = funct7 = 0 ----
        // Con esos campos en 0, los 9 opcodes de la tabla son legales (add, addi, lb, sb, beq,
        // jalr, lui, jal, halt); cualquier otro tiene que dar ilegal sin escrituras.
        for (op = 0; op < 128; op = op + 1) begin
            r_actual = "barrido de opcodes";
            r_instr  = {25'd0, op[6:0]};
            #1;
            case (op[6:0])
                OP_R, OP_I_ARIT, OP_LOAD, OP_STORE, OP_BRANCH, OP_JALR, OP_LUI, OP_JAL, OP_HALT: check_eq("barrido: opcode legal", {31'd0, w_illegal}, 32'd0);
                default: begin
                    if (!w_illegal) $display("  opcode %b deberia ser ilegal", op[6:0]);
                    check_eq("barrido: opcode ilegal", {31'd0, w_illegal}, 32'd1);
                    check_eq("barrido: ilegal con halt", {31'd0, w_halt}, 32'd1);
                    check_eq("barrido: ilegal sin escrituras", {29'd0, w_reg_write, w_mem_write, w_mem_read}, 32'd0);
                end
            endcase
        end

        tb_finish;
    end
endmodule
