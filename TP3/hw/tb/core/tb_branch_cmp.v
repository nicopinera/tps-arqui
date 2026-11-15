`timescale 1ns / 1ps

// Testbench del comparador de igualdad de los branches (US-208).
//
// - Iguales: ceros, unos, valores con signo y pares aleatorios con a = b.
// - Distintos por un solo bit, en cada una de las 32 posiciones y en los dos sentidos: asi se
//   verifica que se comparan los 32 bits (un comparador de menos bits fallaria en alguno).
// - Pares aleatorios distintos.
module tb_branch_cmp;
    `include "tb_utils.vh"

    localparam NBIT = 32;
    localparam N_ALEATORIOS = 1000;

    reg  [NBIT-1:0] r_a = 0;
    reg  [NBIT-1:0] r_b = 0;
    wire            w_eq;

    integer         k;
    integer         semilla = 208;

    branch_cmp #(
        .NBIT(NBIT)
    ) u_branch_cmp (
        .i_a (r_a),
        .i_b (r_b),
        .o_eq(w_eq)
    );

    task comparar;
        input [255:0] nombre;
        input [NBIT-1:0] a;
        input [NBIT-1:0] b;
        begin
            r_a = a;
            r_b = b;
            #1 check_eq(nombre, {31'd0, w_eq}, {31'd0, a == b});
        end
    endtask

    initial begin
        tb_init;

        // ---- Iguales ----
        comparar("iguales: 0 y 0", 32'h0000_0000, 32'h0000_0000);
        comparar("iguales: unos", 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        comparar("iguales: -5", 32'hFFFF_FFFB, 32'hFFFF_FFFB);
        comparar("iguales: minimo negativo", 32'h8000_0000, 32'h8000_0000);

        // ---- Distintos por un solo bit, en cada posicion ----
        for (k = 0; k < NBIT; k = k + 1) begin
            comparar("un bit distinto (a)", 32'h0000_0000 | (32'd1 << k), 32'h0000_0000);
            comparar("un bit distinto (b)", 32'hA5A5_A5A5, 32'hA5A5_A5A5 ^ (32'd1 << k));
        end

        // ---- Signo: -1 y 0xFFFFFFFF son el mismo patron; 1 y -1 no ----
        comparar("1 y -1 son distintos", 32'h0000_0001, 32'hFFFF_FFFF);

        // ---- Aleatorios ----
        for (k = 0; k < N_ALEATORIOS; k = k + 1) begin
            r_a = $random(semilla);
            comparar("aleatorio igual", r_a, r_a);
            comparar("aleatorio", $random(semilla), $random(semilla));
        end

        tb_finish;
    end
endmodule
