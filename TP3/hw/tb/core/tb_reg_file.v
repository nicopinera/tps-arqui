`timescale 1ns / 1ps

// Testbench del banco de registros (US-202, AC1 a AC5).
//
// Los estimulos se cambian en el flanco de bajada y las salidas combinacionales se verifican
// antes del flanco de subida siguiente, asi no hay carreras con la escritura.
module tb_reg_file;
    `include "tb_utils.vh"

    localparam NBIT = 32;
    localparam NREG = 32;
    localparam ADDR_BITS = 5;
    localparam PERIODO = 10;

    reg                     clock = 1'b0;
    reg                     r_clear = 1'b0;
    reg                     r_enable = 1'b0;
    reg                     r_we = 1'b0;
    reg     [ADDR_BITS-1:0] r_rd_addr = 0;
    reg     [     NBIT-1:0] r_wr_data = 0;
    reg     [ADDR_BITS-1:0] r_rs1_addr = 0;
    reg     [ADDR_BITS-1:0] r_rs2_addr = 0;
    reg     [ADDR_BITS-1:0] r_dbg_addr = 0;
    wire    [     NBIT-1:0] w_rs1_data;
    wire    [     NBIT-1:0] w_rs2_data;
    wire    [     NBIT-1:0] w_dbg_data;

    integer                 k;

    reg_file #(
        .NBIT(NBIT),
        .NREG(NREG)
    ) u_reg_file (
        .clock     (clock),
        .i_clear   (r_clear),
        .i_enable  (r_enable),
        .i_we      (r_we),
        .i_rd_addr (r_rd_addr),
        .i_wr_data (r_wr_data),
        .i_rs1_addr(r_rs1_addr),
        .i_rs2_addr(r_rs2_addr),
        .o_rs1_data(w_rs1_data),
        .o_rs2_data(w_rs2_data),
        .i_dbg_addr(r_dbg_addr),
        .o_dbg_data(w_dbg_data)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Valor de prueba distinto para cada registro.
    function [NBIT-1:0] patron;
        input integer n;
        input [7:0] semilla;
        begin
            patron = {semilla, n[7:0], ~semilla, ~n[7:0]};
        end
    endfunction

    // Escribe un registro con i_enable = 1 (un ciclo completo).
    task escribir;
        input [ADDR_BITS-1:0] rd;
        input [NBIT-1:0] dato;
        begin
            @(negedge clock);
            r_enable  = 1'b1;
            r_we      = 1'b1;
            r_rd_addr = rd;
            r_wr_data = dato;
            @(negedge clock);
            r_we     = 1'b0;
            r_enable = 1'b0;
        end
    endtask

    // Lee por el puerto de depuracion y compara.
    task ver_dbg;
        input [255:0] nombre;
        input [ADDR_BITS-1:0] addr;
        input [NBIT-1:0] esperado;
        begin
            r_dbg_addr = addr;
            #1;
            check_eq(nombre, w_dbg_data, esperado);
        end
    endtask

    initial begin
        tb_init;

        // ---- Arranque: borrado con i_enable = 0 ----
        @(negedge clock);
        r_clear = 1'b1;
        @(negedge clock);
        r_clear = 1'b0;
        for (k = 0; k < NREG; k = k + 1) ver_dbg("arranque: todo en 0", k[ADDR_BITS-1:0], 0);

        // ---- Escritura y lectura de x1..x31 por los tres puertos ----
        for (k = 1; k < NREG; k = k + 1) escribir(k[ADDR_BITS-1:0], patron(k, 8'hA5));
        for (k = 1; k < NREG; k = k + 1) begin
            r_rs1_addr = k[ADDR_BITS-1:0];
            r_rs2_addr = NREG - k;  // recorre al reves
            r_dbg_addr = k[ADDR_BITS-1:0];
            #1;
            check_eq("lectura rs1", w_rs1_data, patron(k, 8'hA5));
            check_eq("lectura rs2", w_rs2_data, patron(NREG - k, 8'hA5));
            check_eq("lectura dbg", w_dbg_data, patron(k, 8'hA5));
        end

        // ---- AC1: x0 no se escribe y se lee 0 ----
        escribir(0, 32'hDEAD_BEEF);
        r_rs1_addr = 0;
        r_rs2_addr = 0;
        r_dbg_addr = 0;
        #1;
        check_eq("AC1 x0 por rs1", w_rs1_data, 0);
        check_eq("AC1 x0 por rs2", w_rs2_data, 0);
        check_eq("AC1 x0 por dbg", w_dbg_data, 0);
        // Tampoco hay bypass hacia x0 mientras se intenta escribirlo.
        @(negedge clock);
        r_enable  = 1'b1;
        r_we      = 1'b1;
        r_rd_addr = 0;
        r_wr_data = 32'h1234_5678;
        #1;
        check_eq("AC1 sin bypass a x0 (rs1)", w_rs1_data, 0);
        check_eq("AC1 sin bypass a x0 (rs2)", w_rs2_data, 0);
        @(negedge clock);
        r_we     = 1'b0;
        r_enable = 1'b0;
        ver_dbg("AC1 x0 sigue en 0", 0, 0);

        // ---- AC2: bypass en el mismo ciclo ----
        @(negedge clock);
        r_enable   = 1'b1;
        r_we       = 1'b1;
        r_rd_addr  = 5'd5;
        r_wr_data  = 32'hCAFE_BABE;
        r_rs1_addr = 5'd5;
        r_rs2_addr = 5'd6;
        r_dbg_addr = 5'd5;
        #1;
        check_eq("AC2 bypass rs1", w_rs1_data, 32'hCAFE_BABE);
        check_eq("AC2 rs2 otro reg sin bypass", w_rs2_data, patron(6, 8'hA5));
        check_eq("AC2 dbg ve el valor guardado", w_dbg_data, patron(5, 8'hA5));
        r_rs1_addr = 5'd6;
        r_rs2_addr = 5'd5;
        #1;
        check_eq("AC2 bypass rs2", w_rs2_data, 32'hCAFE_BABE);
        check_eq("AC2 rs1 otro reg sin bypass", w_rs1_data, patron(6, 8'hA5));
        @(negedge clock);
        r_we     = 1'b0;
        r_enable = 1'b0;
        ver_dbg("AC2 x5 quedo escrito", 5'd5, 32'hCAFE_BABE);

        // ---- AC3: con i_enable = 0 no se escribe (ni hay bypass) ----
        @(negedge clock);
        r_enable   = 1'b0;
        r_we       = 1'b1;
        r_rd_addr  = 5'd7;
        r_wr_data  = 32'h0BAD_F00D;
        r_rs1_addr = 5'd7;
        #1;
        check_eq("AC3 sin bypass con enable=0", w_rs1_data, patron(7, 8'hA5));
        @(negedge clock);
        @(negedge clock);
        r_we = 1'b0;
        ver_dbg("AC3 x7 no cambio", 5'd7, patron(7, 8'hA5));

        // ---- AC5: el puerto de depuracion lee mientras rs1/rs2 operan y WB escribe ----
        for (k = 1; k < NREG; k = k + 1) begin
            @(negedge clock);
            r_enable   = 1'b1;
            r_we       = 1'b1;
            r_rd_addr  = k[ADDR_BITS-1:0];
            r_wr_data  = patron(k, 8'h3C);
            r_rs1_addr = k[ADDR_BITS-1:0];  // bypass
            r_rs2_addr = NREG - k;  // otro registro
            r_dbg_addr = k[ADDR_BITS-1:0];  // el mismo que se escribe: valor viejo
            #1;
            check_eq("AC5 rs1 con bypass", w_rs1_data, patron(k, 8'h3C));
            check_eq("AC5 dbg valor guardado", w_dbg_data, (k == 5) ? 32'hCAFE_BABE : patron(k, 8'hA5));
            // rs2 ve un valor nuevo si ese registro ya se reescribio en esta pasada.
            check_eq("AC5 rs2 en paralelo", w_rs2_data, (NREG - k < k) ? patron(NREG - k, 8'h3C) : (NREG - k == k) ? patron(k, 8'h3C) : (NREG - k == 5) ? 32'hCAFE_BABE : patron(NREG - k, 8'hA5));
        end
        @(negedge clock);
        r_we     = 1'b0;
        r_enable = 1'b0;
        for (k = 1; k < NREG; k = k + 1) ver_dbg("AC5 dbg despues del barrido", k[ADDR_BITS-1:0], patron(k, 8'h3C));

        // ---- AC4: i_clear con i_enable = 0, y con prioridad sobre una escritura ----
        @(negedge clock);
        r_clear   = 1'b1;
        r_enable  = 1'b0;
        r_we      = 1'b1;
        r_rd_addr = 5'd9;
        r_wr_data = 32'hFFFF_FFFF;
        @(negedge clock);
        r_clear = 1'b0;
        r_we    = 1'b0;
        for (k = 0; k < NREG; k = k + 1) ver_dbg("AC4 clear con enable=0", k[ADDR_BITS-1:0], 0);

        escribir(5'd9, 32'h0000_0009);
        @(negedge clock);
        r_clear   = 1'b1;
        r_enable  = 1'b1;
        r_we      = 1'b1;
        r_rd_addr = 5'd10;
        r_wr_data = 32'hFFFF_FFFF;
        @(negedge clock);
        r_clear  = 1'b0;
        r_we     = 1'b0;
        r_enable = 1'b0;
        ver_dbg("AC4 clear borra x9", 5'd9, 0);
        ver_dbg("AC4 clear gana a la escritura", 5'd10, 0);

        tb_finish;
    end
endmodule
