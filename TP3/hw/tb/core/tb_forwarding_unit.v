`timescale 1ns / 1ps

// Testbench de la unidad de forwarding (US-301).
//
// - Casos dirigidos: productor a 1 instruccion (EX/MEM), a 2 (MEM/WB), doble coincidencia (gana
//   EX/MEM), rd = x0, productor que no escribe el banco o que es una burbuja, los dos operandos
//   a la vez y ninguna coincidencia.
// - Aleatorio: combinaciones al azar comparadas contra un modelo de referencia escrito con
//   otra estructura (primero calcula las coincidencias y despues elige).
module tb_forwarding_unit;
    `include "tb_utils.vh"

    localparam N_ALEATORIOS = 5000;
    localparam [1:0] FWD_ID_EX = 2'b00;
    localparam [1:0] FWD_MEM_WB = 2'b01;
    localparam [1:0] FWD_EX_MEM = 2'b10;

    reg  [4:0] r_rs1 = 0;
    reg  [4:0] r_rs2 = 0;
    reg  [4:0] r_mem_rd = 0;
    reg        r_mem_we = 0;
    reg        r_mem_valid = 0;
    reg  [4:0] r_wb_rd = 0;
    reg        r_wb_we = 0;
    reg        r_wb_valid = 0;
    wire [1:0] w_fwd_a;
    wire [1:0] w_fwd_b;

    integer    k;
    integer    semilla = 301;

    forwarding_unit u_forwarding_unit (
        .i_id_ex_rs1       (r_rs1),
        .i_id_ex_rs2       (r_rs2),
        .i_ex_mem_rd       (r_mem_rd),
        .i_ex_mem_reg_write(r_mem_we),
        .i_ex_mem_valid    (r_mem_valid),
        .i_mem_wb_rd       (r_wb_rd),
        .i_mem_wb_reg_write(r_wb_we),
        .i_mem_wb_valid    (r_wb_valid),
        .o_fwd_a           (w_fwd_a),
        .o_fwd_b           (w_fwd_b)
    );

    // Modelo de referencia para un operando
    function [1:0] fwd_ref;
        input [4:0] rs;
        reg hay_mem, hay_wb;
        begin
            hay_mem = r_mem_valid && r_mem_we && (r_mem_rd != 0) && (r_mem_rd == rs);
            hay_wb  = r_wb_valid && r_wb_we && (r_wb_rd != 0) && (r_wb_rd == rs);
            case ({
                hay_mem, hay_wb
            })
                2'b10, 2'b11: fwd_ref = FWD_EX_MEM;
                2'b01: fwd_ref = FWD_MEM_WB;
                default: fwd_ref = FWD_ID_EX;
            endcase
        end
    endfunction

    // Fija EX/MEM y MEM/WB (valid = reg_write = 1) y los operandos de EX.
    task presentar;
        input [4:0] rs1;
        input [4:0] rs2;
        input [4:0] mem_rd;
        input [4:0] wb_rd;
        begin
            r_rs1       = rs1;
            r_rs2       = rs2;
            r_mem_rd    = mem_rd;
            r_wb_rd     = wb_rd;
            r_mem_we    = 1'b1;
            r_mem_valid = 1'b1;
            r_wb_we     = 1'b1;
            r_wb_valid  = 1'b1;
            #1;
        end
    endtask

    task ver;
        input [255:0] nombre;
        input [1:0] fwd_a;
        input [1:0] fwd_b;
        begin
            check_eq(nombre, {30'd0, w_fwd_a}, {30'd0, fwd_a});
            check_eq(nombre, {30'd0, w_fwd_b}, {30'd0, fwd_b});
        end
    endtask

    initial begin
        tb_init;

        // add x1, ... ; sub x2, x1, x3: el add esta en MEM
        presentar(5'd1, 5'd3, 5'd1, 5'd9);
        ver("productor a 1: fwd_a = 10", FWD_EX_MEM, FWD_ID_EX);

        // add x1, ... ; otra ; sub x2, x1, x3: el add esta en WB
        presentar(5'd1, 5'd3, 5'd9, 5'd1);
        ver("productor a 2: fwd_a = 01", FWD_MEM_WB, FWD_ID_EX);

        // Lo mismo sobre rs2
        presentar(5'd3, 5'd1, 5'd1, 5'd9);
        ver("rs2 a 1: fwd_b = 10", FWD_ID_EX, FWD_EX_MEM);
        presentar(5'd3, 5'd1, 5'd9, 5'd1);
        ver("rs2 a 2: fwd_b = 01", FWD_ID_EX, FWD_MEM_WB);

        // Doble coincidencia: MEM y WB escriben x1; el de MEM es el mas reciente
        presentar(5'd1, 5'd1, 5'd1, 5'd1);
        ver("doble coincidencia: gana EX/MEM", FWD_EX_MEM, FWD_EX_MEM);

        // Los dos operandos, cada uno de un lugar distinto
        presentar(5'd4, 5'd5, 5'd5, 5'd4);
        ver("rs1 de WB y rs2 de MEM", FWD_MEM_WB, FWD_EX_MEM);

        // rd = x0 nunca reenvia
        presentar(5'd0, 5'd0, 5'd0, 5'd0);
        ver("x0 nunca reenvia", FWD_ID_EX, FWD_ID_EX);
        presentar(5'd0, 5'd2, 5'd0, 5'd2);
        ver("x0 en MEM: rs2 desde WB", FWD_ID_EX, FWD_MEM_WB);

        // Productor que no escribe el banco (store, branch)
        presentar(5'd1, 5'd2, 5'd1, 5'd2);
        r_mem_we = 1'b0;
        r_wb_we  = 1'b0;
        #1 ver("sin reg_write no reenvia", FWD_ID_EX, FWD_ID_EX);
        // MEM no escribe pero WB si: se toma WB
        presentar(5'd1, 5'd3, 5'd1, 5'd1);
        r_mem_we = 1'b0;
        #1 ver("MEM sin reg_write: desde WB", FWD_MEM_WB, FWD_ID_EX);

        // Productor que es una burbuja (valid = 0)
        presentar(5'd1, 5'd2, 5'd1, 5'd2);
        r_mem_valid = 1'b0;
        r_wb_valid  = 1'b0;
        #1 ver("burbuja no reenvia", FWD_ID_EX, FWD_ID_EX);
        presentar(5'd1, 5'd3, 5'd1, 5'd1);
        r_mem_valid = 1'b0;
        #1 ver("burbuja en MEM: desde WB", FWD_MEM_WB, FWD_ID_EX);

        // Ninguna coincidencia
        presentar(5'd6, 5'd7, 5'd8, 5'd9);
        ver("sin coincidencia", FWD_ID_EX, FWD_ID_EX);

        // Aleatorio contra el modelo (registros chicos para que haya coincidencias seguido)
        for (k = 0; k < N_ALEATORIOS; k = k + 1) begin
            r_rs1       = $random(semilla) & 5'd3;
            r_rs2       = $random(semilla) & 5'd3;
            r_mem_rd    = $random(semilla) & 5'd3;
            r_wb_rd     = $random(semilla) & 5'd3;
            r_mem_we    = $random(semilla);
            r_mem_valid = $random(semilla);
            r_wb_we     = $random(semilla);
            r_wb_valid  = $random(semilla);
            #1;
            check_eq("aleatorio fwd_a", {30'd0, w_fwd_a}, {30'd0, fwd_ref(r_rs1)});
            check_eq("aleatorio fwd_b", {30'd0, w_fwd_b}, {30'd0, fwd_ref(r_rs2)});
        end

        tb_finish;
    end
endmodule
