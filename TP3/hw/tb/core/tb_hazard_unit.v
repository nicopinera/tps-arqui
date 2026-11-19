`timescale 1ns / 1ps

// Testbench de la unidad de riesgos: deteccion de load-use (US-302).
//
// - Casos dirigidos: load seguido de una instruccion que usa su rd en rs1 o en rs2 (stall),
//   que no lo usa, que tiene esos bits pero no los lee (lui, tipo I: uses_rs = 0), load a x0,
//   burbuja en EX e instruccion que no es load en EX.
// - Aleatorio: combinaciones al azar contra un modelo de referencia escrito con otra estructura.
module tb_hazard_unit;
    `include "tb_utils.vh"

    localparam N_ALEATORIOS = 5000;

    reg        r_valid = 0;
    reg        r_mem_read = 0;
    reg  [4:0] r_rd = 0;
    reg  [4:0] r_rs1 = 0;
    reg  [4:0] r_rs2 = 0;
    reg        r_uses_rs1 = 0;
    reg        r_uses_rs2 = 0;
    wire       w_stall;

    integer    k;
    integer    semilla = 302;

    hazard_unit u_hazard_unit (
        .i_id_ex_valid   (r_valid),
        .i_id_ex_mem_read(r_mem_read),
        .i_id_ex_rd      (r_rd),
        .i_if_id_rs1     (r_rs1),
        .i_if_id_rs2     (r_rs2),
        .i_uses_rs1      (r_uses_rs1),
        .i_uses_rs2      (r_uses_rs2),
        .o_stall         (w_stall)
    );

    // Modelo de referencia: un stall por cada registro leido que coincide con el rd del load
    function stall_ref;
        input dummy;
        reg coincide_rs1, coincide_rs2;
        begin
            coincide_rs1 = r_uses_rs1 && (r_rs1 == r_rd);
            coincide_rs2 = r_uses_rs2 && (r_rs2 == r_rd);
            if (!r_valid || !r_mem_read || r_rd == 5'd0) stall_ref = 1'b0;
            else stall_ref = coincide_rs1 || coincide_rs2;
        end
    endfunction

    // Load valido en EX con rd = rd_load; instruccion en ID con sus rs y uses_rs.
    task caso;
        input [255:0] nombre;
        input [4:0] rd_load;
        input [4:0] rs1;
        input [4:0] rs2;
        input uses_rs1;
        input uses_rs2;
        input esperado;
        begin
            r_valid    = 1'b1;
            r_mem_read = 1'b1;
            r_rd       = rd_load;
            r_rs1      = rs1;
            r_rs2      = rs2;
            r_uses_rs1 = uses_rs1;
            r_uses_rs2 = uses_rs2;
            #1 check_eq(nombre, {31'd0, w_stall}, {31'd0, esperado});
        end
    endtask

    initial begin
        tb_init;

        // lw x1 + add x3, x1, x4 (R: usa rs1 y rs2)
        caso("lw x1 + add x3,x1,x4", 5'd1, 5'd1, 5'd4, 1, 1, 1);
        // lw x1 + add x3, x4, x1: el rd del load en rs2
        caso("lw x1 + add x3,x4,x1", 5'd1, 5'd4, 5'd1, 1, 1, 1);
        // lw x1 + sw x1, 0(x2): el dato del store
        caso("lw x1 + sw x1,0(x2)", 5'd1, 5'd2, 5'd1, 1, 1, 1);
        // lw x1 + beq x1, x2
        caso("lw x1 + beq x1,x2", 5'd1, 5'd1, 5'd2, 1, 1, 1);
        // lw x1 + addi x3, x1, 5 (I: usa solo rs1)
        caso("lw x1 + addi x3,x1,5", 5'd1, 5'd1, 5'd5, 1, 0, 1);
        // lw x1 + instruccion independiente
        caso("lw x1 + add x3,x4,x5", 5'd1, 5'd4, 5'd5, 1, 1, 0);
        // lw x5 + addi x7, x3, 5: los bits de rs2 valen 5 pero un tipo I no lee rs2
        caso("lw x5 + addi x7,x3,5 (imm)", 5'd5, 5'd3, 5'd5, 1, 0, 0);
        // lw x1 + lui x1: no lee registros (los campos son inmediato)
        caso("lw x1 + lui x1", 5'd1, 5'd1, 5'd1, 0, 0, 0);
        // lw x1 + jal x1: tampoco lee registros
        caso("lw x1 + jal x1", 5'd1, 5'd1, 5'd1, 0, 0, 0);
        // lw x0 + uso de x0: x0 vale siempre 0, no hay nada que esperar
        caso("lw x0 + add x5,x0,x0", 5'd0, 5'd0, 5'd0, 1, 1, 0);

        // Lo que esta en EX no es un load
        caso("add x1 en EX: no frena", 5'd1, 5'd1, 5'd1, 1, 1, 1);
        r_mem_read = 1'b0;
        #1 check_eq("add x1 en EX: sin mem_read", {31'd0, w_stall}, 32'd0);
        // Burbuja en EX
        caso("burbuja en EX: no frena", 5'd1, 5'd1, 5'd1, 1, 1, 1);
        r_valid = 1'b0;
        #1 check_eq("burbuja en EX: sin valid", {31'd0, w_stall}, 32'd0);

        // Aleatorio contra el modelo (registros chicos para que haya coincidencias seguido)
        for (k = 0; k < N_ALEATORIOS; k = k + 1) begin
            r_valid    = $random(semilla);
            r_mem_read = $random(semilla);
            r_rd       = $random(semilla) & 5'd3;
            r_rs1      = $random(semilla) & 5'd3;
            r_rs2      = $random(semilla) & 5'd3;
            r_uses_rs1 = $random(semilla);
            r_uses_rs2 = $random(semilla);
            #1 check_eq("aleatorio", {31'd0, w_stall}, {31'd0, stall_ref(1'b0)});
        end

        tb_finish;
    end
endmodule
