`timescale 1ns / 1ps

// Testbench de la memoria de instrucciones (US-204, AC1 y AC5).
//
// - Escritura por el puerto de la Debug Unit de las 256 palabras y lectura combinacional por PC.
// - Los bits bajos y altos del PC se ignoran (ADR-008).
// - La escritura es sincronica: el dato nuevo aparece recien despues del flanco.
// - Precarga con INIT_FILE (hw/tb/common/ejemplo.hex, el mismo de tb_readmemh).
//
// Los estimulos se cambian en el flanco de bajada y las lecturas se verifican antes del
// flanco de subida siguiente.
module tb_instr_mem;
    `include "tb_utils.vh"

    localparam DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam PERIODO = 10;
    localparam [31:0] BYTES_IMEM = 4 * DEPTH;  // 0x400: a partir de aca la memoria da la vuelta

    reg                     clock = 1'b0;
    reg     [         31:0] r_pc = 0;
    reg                     r_we = 1'b0;
    reg     [ADDR_BITS-1:0] r_addr = 0;
    reg     [         31:0] r_wdata = 0;
    wire    [         31:0] w_instr;
    wire    [         31:0] w_instr_init;

    integer                 k;

    instr_mem #(
        .DEPTH(DEPTH)
    ) u_instr_mem (
        .clock  (clock),
        .i_pc   (r_pc),
        .o_instr(w_instr),
        .i_we   (r_we),
        .i_addr (r_addr),
        .i_wdata(r_wdata)
    );

    // Segunda instancia, solo para probar la precarga con $readmemh.
    instr_mem #(
        .DEPTH    (DEPTH),
        .INIT_FILE("hw/tb/common/ejemplo.hex")
    ) u_instr_mem_init (
        .clock  (clock),
        .i_pc   (r_pc),
        .o_instr(w_instr_init),
        .i_we   (1'b0),
        .i_addr ({ADDR_BITS{1'b0}}),
        .i_wdata(32'h0000_0000)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Contenido de prueba de la palabra k: distinto en cada palabra y en cada byte.
    function [31:0] patron;
        input integer indice;
        begin
            patron = {indice[7:0], ~indice[7:0], 8'h5A, indice[7:0] ^ 8'hC3};
        end
    endfunction

    // Escribe una palabra por el puerto de la Debug Unit (un ciclo con i_we = 1).
    task escribir;
        input [ADDR_BITS-1:0] addr;
        input [31:0] dato;
        begin
            r_we    = 1'b1;
            r_addr  = addr;
            r_wdata = dato;
            @(posedge clock);
            @(negedge clock);
            r_we = 1'b0;
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);

        // ---- Precarga con INIT_FILE ----
        r_pc = 32'h0000_0000;
        #1 check_eq("init: palabra 0 (addi x1,x0,5)", w_instr_init, 32'h0050_0093);
        r_pc = 32'h0000_0004;
        #1 check_eq("init: palabra 1 (addi x2,x0,10)", w_instr_init, 32'h00A0_0113);
        r_pc = 32'h0000_0008;
        #1 check_eq("init: palabra 2 (add x3,x1,x2)", w_instr_init, 32'h0020_81B3);
        r_pc = 32'h0000_000C;
        #1 check_eq("init: palabra 3 (HALT)", w_instr_init, 32'h0000_000B);

        // ---- AC5: la Debug Unit escribe las 256 palabras ----
        for (k = 0; k < DEPTH; k = k + 1) escribir(k[ADDR_BITS-1:0], patron(k));

        // ---- AC1: lectura combinacional, en el mismo ciclo en que se presenta el PC ----
        // Se cambia el PC entre flancos y se mira la salida 1 ns despues, sin esperar reloj.
        for (k = 0; k < DEPTH; k = k + 1) begin
            r_pc = 4 * k;
            #1 check_eq("AC1 lectura por PC", w_instr, patron(k));
        end

        // Los 2 bits bajos del PC no direccionan: pc = 4k+1, 4k+2 y 4k+3 leen la palabra k.
        for (k = 0; k < DEPTH; k = k + 1) begin
            r_pc = 4 * k + (k % 3) + 1;
            #1 check_eq("PC[1:0] se ignora", w_instr, patron(k));
        end

        // Fuera de rango la memoria da la vuelta (ADR-008).
        r_pc = BYTES_IMEM;
        #1 check_eq("PC 0x400 lee la palabra 0", w_instr, patron(0));
        r_pc = BYTES_IMEM + 32'h0000_0014;
        #1 check_eq("PC 0x414 lee la palabra 5", w_instr, patron(5));
        r_pc = 32'hFFFF_FFFC;
        #1 check_eq("PC 0xFFFFFFFC lee la 255", w_instr, patron(255));

        // ---- La escritura es sincronica ----
        @(negedge clock);
        r_pc    = 32'h0000_0010;  // palabra 4
        r_we    = 1'b1;
        r_addr  = 4;
        r_wdata = 32'hDEAD_BEEF;
        #1 check_eq("antes del flanco: dato viejo", w_instr, patron(4));
        @(posedge clock);
        #1 check_eq("despues del flanco: dato nuevo", w_instr, 32'hDEAD_BEEF);
        @(negedge clock);
        r_we = 1'b0;

        // Con i_we = 0 no se escribe nada aunque cambien la direccion y el dato.
        r_addr  = 4;
        r_wdata = 32'h1234_5678;
        repeat (3) @(posedge clock);
        @(negedge clock);
        check_eq("i_we = 0 no escribe", w_instr, 32'hDEAD_BEEF);
        check_eq("las vecinas no cambian (3)", u_instr_mem.r_mem[3], patron(3));
        check_eq("las vecinas no cambian (5)", u_instr_mem.r_mem[5], patron(5));

        // AC1: si el PC no cambia, la instruccion tampoco (el nucleo congelado no mueve el PC).
        r_pc = 32'h0000_0020;
        repeat (5) begin
            @(negedge clock);
            check_eq("PC fijo: instruccion fija", w_instr, patron(8));
        end

        tb_finish;
    end
endmodule
