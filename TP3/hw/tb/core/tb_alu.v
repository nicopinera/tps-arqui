`timescale 1ns / 1ps

// Testbench de la ALU de 32 bits (US-201, AC1).
// Tabla de vectores con los casos borde de cada operacion. En cada vector se verifican
// o_result y o_zero.
module tb_alu;
    `include "tb_utils.vh"
    `include "alu_defs.vh"

    localparam NBIT = 32;

    reg  [NBIT-1:0] r_a;
    reg  [NBIT-1:0] r_b;
    reg  [     3:0] r_alu_ctrl;
    wire [NBIT-1:0] w_result;
    wire            w_zero;

    alu #(
        .NBIT(NBIT)
    ) u_alu (
        .i_a       (r_a),
        .i_b       (r_b),
        .i_alu_ctrl(r_alu_ctrl),
        .o_result  (w_result),
        .o_zero    (w_zero)
    );

    // Aplica un vector, espera que la logica combinacional se asiente y compara.
    task probar;
        input [255:0] nombre;  // hasta 32 caracteres
        input [3:0] ctrl;
        input [NBIT-1:0] a;
        input [NBIT-1:0] b;
        input [NBIT-1:0] esperado;
        begin
            r_alu_ctrl = ctrl;
            r_a        = a;
            r_b        = b;
            #1;
            check_eq(nombre, w_result, esperado);
            check_eq(nombre, {31'd0, w_zero}, {31'd0, esperado == {NBIT{1'b0}}});
        end
    endtask

    initial begin
        tb_init;

        // ---- ADD: modulo 2^32, sin overflow ----
        probar("ADD 0 + 0", ALU_ADD, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
        probar("ADD 1 + 2", ALU_ADD, 32'h0000_0001, 32'h0000_0002, 32'h0000_0003);
        probar("ADD 7FFFFFFF + 1", ALU_ADD, 32'h7FFF_FFFF, 32'h0000_0001, 32'h8000_0000);
        probar("ADD -1 + 1", ALU_ADD, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);
        probar("ADD -1 + -1", ALU_ADD, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE);
        probar("ADD 80000000 + 80000000", ALU_ADD, 32'h8000_0000, 32'h8000_0000, 32'h0000_0000);
        probar("ADD 12345678 + 87654321", ALU_ADD, 32'h1234_5678, 32'h8765_4321, 32'h9999_9999);

        // ---- SUB ----
        probar("SUB 5 - 3", ALU_SUB, 32'h0000_0005, 32'h0000_0003, 32'h0000_0002);
        probar("SUB 0 - 1", ALU_SUB, 32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF);
        probar("SUB 80000000 - 1", ALU_SUB, 32'h8000_0000, 32'h0000_0001, 32'h7FFF_FFFF);
        probar("SUB 3 - 3", ALU_SUB, 32'h0000_0003, 32'h0000_0003, 32'h0000_0000);
        probar("SUB 1 - (-1)", ALU_SUB, 32'h0000_0001, 32'hFFFF_FFFF, 32'h0000_0002);

        // ---- SLL: solo cuentan b[4:0] ----
        probar("SLL 1 << 0", ALU_SLL, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);
        probar("SLL 1 << 31", ALU_SLL, 32'h0000_0001, 32'h0000_001F, 32'h8000_0000);
        probar("SLL FFFFFFFF << 4", ALU_SLL, 32'hFFFF_FFFF, 32'h0000_0004, 32'hFFFF_FFF0);
        probar("SLL 12345678 << 8", ALU_SLL, 32'h1234_5678, 32'h0000_0008, 32'h3456_7800);
        probar("SLL 1 << 33 (usa b[4:0])", ALU_SLL, 32'h0000_0001, 32'h0000_0021, 32'h0000_0002);
        probar("SLL 80000000 << 1", ALU_SLL, 32'h8000_0000, 32'h0000_0001, 32'h0000_0000);

        // ---- SLT: con signo ----
        probar("SLT -1 < 1", ALU_SLT, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0001);
        probar("SLT 1 < -1", ALU_SLT, 32'h0000_0001, 32'hFFFF_FFFF, 32'h0000_0000);
        probar("SLT 5 < 5", ALU_SLT, 32'h0000_0005, 32'h0000_0005, 32'h0000_0000);
        probar("SLT MIN < MAX", ALU_SLT, 32'h8000_0000, 32'h7FFF_FFFF, 32'h0000_0001);
        probar("SLT MAX < MIN", ALU_SLT, 32'h7FFF_FFFF, 32'h8000_0000, 32'h0000_0000);
        probar("SLT -2 < -1", ALU_SLT, 32'hFFFF_FFFE, 32'hFFFF_FFFF, 32'h0000_0001);

        // ---- SLTU: sin signo (-1 es el mayor) ----
        probar("SLTU -1 < 1", ALU_SLTU, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);
        probar("SLTU 1 < -1", ALU_SLTU, 32'h0000_0001, 32'hFFFF_FFFF, 32'h0000_0001);
        probar("SLTU 0 < 0", ALU_SLTU, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
        probar("SLTU 7FFFFFFF < 80000000", ALU_SLTU, 32'h7FFF_FFFF, 32'h8000_0000, 32'h0000_0001);
        probar("SLTU 0 < 1", ALU_SLTU, 32'h0000_0000, 32'h0000_0001, 32'h0000_0001);

        // ---- XOR ----
        probar("XOR F0F0F0F0 ^ FFFF0000", ALU_XOR, 32'hF0F0_F0F0, 32'hFFFF_0000, 32'h0F0F_F0F0);
        probar("XOR A ^ A", ALU_XOR, 32'hDEAD_BEEF, 32'hDEAD_BEEF, 32'h0000_0000);
        probar("XOR 0 ^ FFFFFFFF", ALU_XOR, 32'h0000_0000, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

        // ---- SRL: logico, entra 0 por la izquierda ----
        probar("SRL 80000000 >> 31", ALU_SRL, 32'h8000_0000, 32'h0000_001F, 32'h0000_0001);
        probar("SRL 80000000 >> 0", ALU_SRL, 32'h8000_0000, 32'h0000_0000, 32'h8000_0000);
        probar("SRL FFFFFFFF >> 4", ALU_SRL, 32'hFFFF_FFFF, 32'h0000_0004, 32'h0FFF_FFFF);
        probar("SRL 12345678 >> 8", ALU_SRL, 32'h1234_5678, 32'h0000_0008, 32'h0012_3456);
        probar("SRL >> 32 (usa b[4:0])", ALU_SRL, 32'h8000_0000, 32'h0000_0020, 32'h8000_0000);

        // ---- SRA: aritmetico, replica el bit de signo ----
        probar("SRA 80000000 >> 31", ALU_SRA, 32'h8000_0000, 32'h0000_001F, 32'hFFFF_FFFF);
        probar("SRA 80000000 >> 0", ALU_SRA, 32'h8000_0000, 32'h0000_0000, 32'h8000_0000);
        probar("SRA F0000000 >> 4", ALU_SRA, 32'hF000_0000, 32'h0000_0004, 32'hFF00_0000);
        probar("SRA 70000000 >> 4 (pos)", ALU_SRA, 32'h7000_0000, 32'h0000_0004, 32'h0700_0000);
        probar("SRA -16 >> 2", ALU_SRA, 32'hFFFF_FFF0, 32'h0000_0002, 32'hFFFF_FFFC);
        probar("SRA 7FFFFFFF >> 31", ALU_SRA, 32'h7FFF_FFFF, 32'h0000_001F, 32'h0000_0000);
        probar("SRA >> FFFFFFE1 (b[4:0])", ALU_SRA, 32'h8000_0000, 32'hFFFF_FFE1, 32'hC000_0000);

        // ---- OR ----
        probar("OR F0F0F0F0 | 0F0F0F0F", ALU_OR, 32'hF0F0_F0F0, 32'h0F0F_0F0F, 32'hFFFF_FFFF);
        probar("OR 0 | 0", ALU_OR, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
        probar("OR 12340000 | 00005678", ALU_OR, 32'h1234_0000, 32'h0000_5678, 32'h1234_5678);

        // ---- AND ----
        probar("AND F0F0F0F0 & 0F0F0F0F", ALU_AND, 32'hF0F0_F0F0, 32'h0F0F_0F0F, 32'h0000_0000);
        probar("AND FFFFFFFF & 12345678", ALU_AND, 32'hFFFF_FFFF, 32'h1234_5678, 32'h1234_5678);
        probar("AND FF00FF00 & 0FF00FF0", ALU_AND, 32'hFF00_FF00, 32'h0FF0_0FF0, 32'h0F00_0F00);

        // ---- PASS_B (lui): ignora A ----
        probar("PASS_B 12345000", ALU_PASS_B, 32'hDEAD_BEEF, 32'h1234_5000, 32'h1234_5000);
        probar("PASS_B FFFFF000", ALU_PASS_B, 32'h0000_0000, 32'hFFFF_F000, 32'hFFFF_F000);
        probar("PASS_B 0", ALU_PASS_B, 32'hFFFF_FFFF, 32'h0000_0000, 32'h0000_0000);

        // ---- codigos sin operacion asignada: resultado 0 ----
        probar("ctrl 1001 sin uso", 4'b1001, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);
        probar("ctrl 1110 sin uso", 4'b1110, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);

        tb_finish;
    end
endmodule
