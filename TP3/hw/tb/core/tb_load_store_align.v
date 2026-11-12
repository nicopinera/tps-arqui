`timescale 1ns / 1ps

// Testbench de la alineacion de stores y la extension de loads (US-205, AC1 a AC5).
//
// Conecta store_align -> data_mem -> load_extend como en la etapa MEM. El testbench lleva un
// modelo de referencia por BYTE (r_ref, little-endian, desalineados segun ADR-018), escrito sin
// byte enables ni seleccion por carriles, para no repetir la logica del RTL.
//
// Se usa una region de REGION_PALABRAS palabras al principio de la DMEM.
// Los estimulos se cambian en el flanco de bajada y las lecturas se verifican antes del
// flanco de subida siguiente.
module tb_load_store_align;
    `include "tb_utils.vh"
    `include "control_defs.vh"

    localparam DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam PERIODO = 10;
    localparam REGION_PALABRAS = 16;
    localparam REGION_BYTES = 4 * REGION_PALABRAS;

    reg                     clock = 1'b0;
    reg                     r_enable = 1'b0;
    reg                     r_we = 1'b0;
    reg                     r_dbg_we = 1'b0;
    reg     [ADDR_BITS-1:0] r_dbg_wr_addr = 0;
    reg     [          2:0] r_funct3 = 0;
    reg     [         31:0] r_addr = 0;
    reg     [         31:0] r_rs2 = 0;

    wire    [          3:0] w_be;
    wire    [         31:0] w_wdata;
    wire    [         31:0] w_word;
    wire    [         31:0] w_load;

    // Sin uso en este testbench
    wire    [         31:0] w_dbg_data;
    wire                    w_dbg_used;
    wire    [  ADDR_BITS:0] w_used_count;

    // Modelo de referencia: un byte por direccion
    reg     [          7:0] r_ref      [0:REGION_BYTES-1];

    reg     [        255:0] r_actual;  // operacion que se esta probando (para el mensaje de falla)
    integer                 k;
    integer                 f;
    integer                 off;
    integer                 v;

    // ---- Etapa MEM: store_align -> data_mem -> load_extend ----
    store_align u_store_align (
        .i_funct3  (r_funct3),
        .i_addr_low(r_addr[1:0]),
        .i_data    (r_rs2),
        .o_be      (w_be),
        .o_data    (w_wdata)
    );

    data_mem #(
        .DEPTH(DEPTH)
    ) u_data_mem (
        .clock        (clock),
        .i_enable     (r_enable),
        .i_clear_used (1'b0),
        .i_we         (r_we),
        .i_valid      (1'b1),
        .i_addr       (r_addr),
        .i_be         (w_be),
        .i_wdata      (w_wdata),
        .o_rdata      (w_word),
        .i_dbg_we     (r_dbg_we),
        .i_dbg_wr_addr(r_dbg_wr_addr),
        .i_dbg_addr   ({ADDR_BITS{1'b0}}),
        .o_dbg_data   (w_dbg_data),
        .o_dbg_used   (w_dbg_used),
        .o_used_count (w_used_count)
    );

    load_extend u_load_extend (
        .i_funct3  (r_funct3),
        .i_addr_low(r_addr[1:0]),
        .i_word    (w_word),
        .o_data    (w_load)
    );

    always #(PERIODO / 2) clock = ~clock;

    // ---- Modelo de referencia (ADR-018: little-endian, desalineados ignoran los bits bajos) ----
    task ref_store;
        input [2:0] funct3;
        input integer addr;
        input [31:0] valor;
        integer a;
        begin
            case (funct3)
                F3_SB: r_ref[addr] = valor[7:0];
                F3_SH: begin
                    a = addr - (addr % 2);
                    r_ref[a]   = valor[7:0];
                    r_ref[a+1] = valor[15:8];
                end
                F3_SW: begin
                    a = addr - (addr % 4);
                    r_ref[a]   = valor[7:0];
                    r_ref[a+1] = valor[15:8];
                    r_ref[a+2] = valor[23:16];
                    r_ref[a+3] = valor[31:24];
                end
                default: ;  // no es un store: no escribe
            endcase
        end
    endtask

    function [31:0] ref_load;
        input [2:0] funct3;
        input integer addr;
        integer a;
        begin
            case (funct3)
                F3_LB:  ref_load = {{24{r_ref[addr][7]}}, r_ref[addr]};
                F3_LBU: ref_load = {24'd0, r_ref[addr]};
                F3_LH: begin
                    a = addr - (addr % 2);
                    ref_load = {{16{r_ref[a+1][7]}}, r_ref[a+1], r_ref[a]};
                end
                F3_LHU: begin
                    a = addr - (addr % 2);
                    ref_load = {16'd0, r_ref[a+1], r_ref[a]};
                end
                F3_LW: begin
                    a = addr - (addr % 4);
                    ref_load = {r_ref[a+3], r_ref[a+2], r_ref[a+1], r_ref[a]};
                end
                default: ref_load = 32'h0000_0000;
            endcase
        end
    endfunction

    // ---- Operaciones sobre el hardware ----
    // Store: un ciclo con we = enable = 1; actualiza el modelo.
    task store;
        input [255:0] nombre;
        input [2:0] funct3;
        input integer addr;
        input [31:0] valor;
        begin
            r_actual = nombre;
            r_funct3 = funct3;
            r_addr   = addr;
            r_rs2    = valor;
            r_we     = 1'b1;
            r_enable = 1'b1;
            @(posedge clock);
            ref_store(funct3, addr, valor);
            @(negedge clock);
            r_we     = 1'b0;
            r_enable = 1'b0;
        end
    endtask

    // Load: combinacional; compara la salida de load_extend con el valor esperado.
    task load;
        input [255:0] nombre;
        input [2:0] funct3;
        input integer addr;
        input [31:0] esperado;
        begin
            r_actual = nombre;
            r_funct3 = funct3;
            r_addr   = addr;
            #1;
            if (w_load !== esperado)
                $display("  en: %0s (funct3 = %b, addr = 0x%0h)", r_actual, funct3, addr);
            check_eq(nombre, w_load, esperado);
        end
    endtask

    // Lee con lw todas las palabras de la region y las compara con el modelo.
    task comparar_region;
        input [255:0] nombre;
        integer p;
        begin
            for (p = 0; p < REGION_PALABRAS; p = p + 1) load(nombre, F3_LW, 4 * p, ref_load(F3_LW, 4 * p));
        end
    endtask

    // Valores de prueba: cada byte y cada media palabra con el bit de signo en 0 y en 1, y medias
    // palabras con el bit 15 distinto del bit 7 (detecta extender lh con el signo equivocado).
    function [31:0] patron;
        input integer i;
        begin
            case (i % 8)
                0: patron = 32'h807F_7F80;  // mitades: b15=1/b7=0 y b15=0/b7=1
                1: patron = 32'h7F80_807F;
                2: patron = 32'hFFFF_FFFF;
                3: patron = 32'h0000_0000;
                4: patron = 32'h8000_0080;
                5: patron = 32'h7FFF_FF7F;
                6: patron = 32'h1122_3344;
                default: patron = 32'hA1B2_C3D4;
            endcase
        end
    endfunction

    initial begin
        tb_init;
        @(negedge clock);

        // ---- Region en cero (como la limpieza de un LOAD) ----
        for (k = 0; k < REGION_PALABRAS; k = k + 1) begin
            r_dbg_we      = 1'b1;
            r_dbg_wr_addr = k;
            @(posedge clock);
            @(negedge clock);
        end
        r_dbg_we = 1'b0;
        for (k = 0; k < REGION_BYTES; k = k + 1) r_ref[k] = 8'h00;
        comparar_region("region inicial en cero");

        // ---- AC3: little-endian ----
        store("AC3 sw 0x11223344 en 0", F3_SW, 0, 32'h1122_3344);
        load("AC3 lbu 0 = 0x44", F3_LBU, 0, 32'h0000_0044);
        load("AC3 lbu 1 = 0x33", F3_LBU, 1, 32'h0000_0033);
        load("AC3 lbu 2 = 0x22", F3_LBU, 2, 32'h0000_0022);
        load("AC3 lbu 3 = 0x11", F3_LBU, 3, 32'h0000_0011);
        load("AC3 lhu 0 = 0x3344", F3_LHU, 0, 32'h0000_3344);
        load("AC3 lhu 2 = 0x1122", F3_LHU, 2, 32'h0000_1122);

        // ---- AC1: sb en cada offset modifica solo ese byte ----
        for (off = 0; off < 4; off = off + 1) begin
            store("AC1 sw base", F3_SW, 4 + 4 * off, 32'h1122_3344);
            store("AC1 sb 0xAA", F3_SB, 4 + 4 * off + off, 32'hFFFF_FFAA);
        end
        load("AC1 sb offset 0", F3_LW, 4, 32'h1122_33AA);
        load("AC1 sb offset 1", F3_LW, 8, 32'h1122_AA44);
        load("AC1 sb offset 2", F3_LW, 12, 32'h11AA_3344);
        load("AC1 sb offset 3", F3_LW, 16, 32'hAA22_3344);

        // sh en offsets 0 y 2 modifica solo esa media palabra
        store("AC1 sw base", F3_SW, 20, 32'h1122_3344);
        store("AC1 sh 0xBEEF en 20", F3_SH, 20, 32'hFFFF_BEEF);
        load("AC1 sh offset 0", F3_LW, 20, 32'h1122_BEEF);
        store("AC1 sw base", F3_SW, 24, 32'h1122_3344);
        store("AC1 sh 0xBEEF en 26", F3_SH, 26, 32'hFFFF_BEEF);
        load("AC1 sh offset 2", F3_LW, 24, 32'hBEEF_3344);
        comparar_region("AC1 resto de la region");

        // ---- AC2: extension con signo y con ceros ----
        store("AC2 sb 0x80", F3_SB, 28, 32'h0000_0080);
        load("AC2 lb 0x80", F3_LB, 28, 32'hFFFF_FF80);
        load("AC2 lbu 0x80", F3_LBU, 28, 32'h0000_0080);
        store("AC2 sh 0x8000", F3_SH, 30, 32'h0000_8000);
        load("AC2 lh 0x8000", F3_LH, 30, 32'hFFFF_8000);
        load("AC2 lhu 0x8000", F3_LHU, 30, 32'h0000_8000);
        store("AC2 sb 0x7F", F3_SB, 29, 32'h0000_007F);
        load("AC2 lb 0x7F (positivo)", F3_LB, 29, 32'h0000_007F);

        // ---- AC4: desalineados (ADR-018) ----
        store("AC4 sw base", F3_SW, 32, 32'hA1B2_C3D4);
        load("AC4 lw en 34 = palabra de 32", F3_LW, 34, 32'hA1B2_C3D4);
        load("AC4 lw en 33", F3_LW, 33, 32'hA1B2_C3D4);
        load("AC4 lw en 35", F3_LW, 35, 32'hA1B2_C3D4);
        load("AC4 lh en 35 = media de 34", F3_LH, 35, 32'hFFFF_A1B2);
        load("AC4 lhu en 33 = media de 32", F3_LHU, 33, 32'h0000_C3D4);
        store("AC4 sw en 39 = palabra de 36", F3_SW, 39, 32'h0102_0304);
        load("AC4 lw en 36", F3_LW, 36, 32'h0102_0304);
        store("AC4 sh en 37 = media de 36", F3_SH, 37, 32'h0000_EEFF);
        load("AC4 lw en 36 tras sh", F3_LW, 36, 32'h0102_EEFF);
        comparar_region("AC4 resto de la region");

        // ---- AC5: todas las combinaciones tamano x offset x signo contra el modelo ----
        // Loads: 5 tipos x 4 offsets x 8 palabras de prueba.
        for (v = 0; v < 8; v = v + 1) begin
            store("AC5 palabra de prueba", F3_SW, 40, patron(v));
            for (off = 0; off < 4; off = off + 1) begin
                load("AC5 lb", F3_LB, 40 + off, ref_load(F3_LB, 40 + off));
                load("AC5 lbu", F3_LBU, 40 + off, ref_load(F3_LBU, 40 + off));
                load("AC5 lh", F3_LH, 40 + off, ref_load(F3_LH, 40 + off));
                load("AC5 lhu", F3_LHU, 40 + off, ref_load(F3_LHU, 40 + off));
                load("AC5 lw", F3_LW, 40 + off, ref_load(F3_LW, 40 + off));
            end
        end

        // Stores: 3 tipos x 4 offsets x 4 valores; despues de cada uno se compara la region.
        for (v = 0; v < 4; v = v + 1) begin
            for (off = 0; off < 4; off = off + 1) begin
                store("AC5 sb", F3_SB, 44 + off, patron(v + 8));
                comparar_region("AC5 region tras sb");
                store("AC5 sh", F3_SH, 48 + off, patron(v + 12));
                comparar_region("AC5 region tras sh");
                store("AC5 sw", F3_SW, 52 + off, patron(v + 16));
                comparar_region("AC5 region tras sw");
            end
        end

        // ---- funct3 que no son stores ni loads ----
        // Un funct3 que no es store da be = 0000: aunque llegue mem_write, no se escribe nada.
        for (f = 0; f < 8; f = f + 1) begin
            if (f != F3_SB && f != F3_SH && f != F3_SW) begin
                store("funct3 no store", f[2:0], 56, 32'hBAD0_BAD0);
            end
        end
        comparar_region("funct3 no store no escribe");
        // Un funct3 que no es load da 0.
        store("palabra para loads invalidos", F3_SW, 60, 32'hFFFF_FFFF);
        for (f = 0; f < 8; f = f + 1) begin
            if (f != F3_LB && f != F3_LH && f != F3_LW && f != F3_LBU && f != F3_LHU)
                load("funct3 no load da 0", f[2:0], 60, 32'h0000_0000);
        end

        tb_finish;
    end
endmodule
