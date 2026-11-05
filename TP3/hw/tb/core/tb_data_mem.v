`timescale 1ns / 1ps

// Testbench de la memoria de datos con bitmap de memoria usada.
//
// El testbench lleva un modelo propio (r_modelo, r_modelo_used, n_usadas) que se actualiza en
// cada escritura. La task comparar_todo recorre las 256 palabras por el puerto de la Debug
// Unit y compara dato, bit del bitmap y contador contra el modelo.
//
// Los estimulos se cambian en el flanco de bajada y las salidas se verifican antes del
// flanco de subida siguiente.
module tb_data_mem;
    `include "tb_utils.vh"

    localparam DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam PERIODO = 10;
    localparam [31:0] BYTES_DMEM = 4 * DEPTH;  // 0x400: a partir de aca la memoria da la vuelta

    reg                     clock = 1'b0;
    reg                     r_enable = 1'b0;
    reg                     r_clear_used = 1'b0;
    reg                     r_we = 1'b0;
    reg                     r_valid = 1'b0;
    reg     [         31:0] r_addr = 0;
    reg     [          3:0] r_be = 0;
    reg     [         31:0] r_wdata = 0;
    wire    [         31:0] w_rdata;
    reg                     r_dbg_we = 1'b0;
    reg     [ADDR_BITS-1:0] r_dbg_wr_addr = 0;
    reg     [ADDR_BITS-1:0] r_dbg_addr = 0;
    wire    [         31:0] w_dbg_data;
    wire                    w_dbg_used;
    wire    [  ADDR_BITS:0] w_used_count;

    // Modelo de referencia
    reg     [         31:0] r_modelo            [0:DEPTH-1];
    reg     [    DEPTH-1:0] r_modelo_used;
    integer                 n_usadas;

    integer                 k;
    integer                 j;

    data_mem #(
        .DEPTH(DEPTH)
    ) u_data_mem (
        .clock        (clock),
        .i_enable     (r_enable),
        .i_clear_used (r_clear_used),
        .i_we         (r_we),
        .i_valid      (r_valid),
        .i_addr       (r_addr),
        .i_be         (r_be),
        .i_wdata      (r_wdata),
        .o_rdata      (w_rdata),
        .i_dbg_we     (r_dbg_we),
        .i_dbg_wr_addr(r_dbg_wr_addr),
        .i_dbg_addr   (r_dbg_addr),
        .o_dbg_data   (w_dbg_data),
        .o_dbg_used   (w_dbg_used),
        .o_used_count (w_used_count)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Actualiza el modelo con un store efectivo del nucleo.
    task modelo_store;
        input [31:0] addr;
        input [3:0] be;
        input [31:0] dato;
        reg [ADDR_BITS-1:0] palabra;
        begin
            palabra = addr[ADDR_BITS+1:2];
            for (j = 0; j < 4; j = j + 1) if (be[j]) r_modelo[palabra][8*j+:8] = dato[8*j+:8];
            if (!r_modelo_used[palabra]) n_usadas = n_usadas + 1;
            r_modelo_used[palabra] = 1'b1;
        end
    endtask

    // Un ciclo de reloj con las senales del nucleo que se pasan; despues todo vuelve a 0.
    // El modelo solo se actualiza si el store es efectivo (enable && we && valid).
    task ciclo_nucleo;
        input enable, we, valid;
        input [31:0] addr;
        input [3:0] be;
        input [31:0] dato;
        begin
            r_enable = enable;
            r_we     = we;
            r_valid  = valid;
            r_addr   = addr;
            r_be     = be;
            r_wdata  = dato;
            @(posedge clock);
            if (enable && we && valid) modelo_store(addr, be, dato);
            @(negedge clock);
            r_enable = 1'b0;
            r_we     = 1'b0;
            r_valid  = 1'b0;
        end
    endtask

    // Store normal del nucleo (enable = we = valid = 1).
    task store;
        input [31:0] addr;
        input [3:0] be;
        input [31:0] dato;
        begin
            ciclo_nucleo(1'b1, 1'b1, 1'b1, addr, be, dato);
        end
    endtask

    // Limpieza de una palabra por la Debug Unit (con el nucleo congelado).
    task limpiar_du;
        input [ADDR_BITS-1:0] addr;
        begin
            r_dbg_we      = 1'b1;
            r_dbg_wr_addr = addr;
            @(posedge clock);
            r_modelo[addr] = 32'h0000_0000;
            @(negedge clock);
            r_dbg_we = 1'b0;
        end
    endtask

    // Pulso de i_clear_used (un ciclo).
    task borrar_usadas;
        begin
            r_clear_used = 1'b1;
            @(posedge clock);
            r_modelo_used = {DEPTH{1'b0}};
            n_usadas      = 0;
            @(negedge clock);
            r_clear_used = 1'b0;
        end
    endtask

    // Recorre las 256 palabras por el puerto de la Debug Unit y compara con el modelo.
    task comparar_todo;
        input [255:0] nombre;
        begin
            for (k = 0; k < DEPTH; k = k + 1) begin
                r_dbg_addr = k;
                #1;
                if (w_dbg_data !== r_modelo[k] || w_dbg_used !== r_modelo_used[k]) $display("  %0s: palabra %0d", nombre, k);
                check_eq(nombre, w_dbg_data, r_modelo[k]);
                check_eq(nombre, {31'd0, w_dbg_used}, {31'd0, r_modelo_used[k]});
            end
            check_eq(nombre, {23'd0, w_used_count}, n_usadas);
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);

        // ---- Arranque como en un LOAD: borra el bitmap y limpia las 256 palabras ----
        borrar_usadas;
        for (k = 0; k < DEPTH; k = k + 1) limpiar_du(k[ADDR_BITS-1:0]);
        comparar_todo("AC4 limpieza inicial");

        // ---- AC2: stores que no tienen que escribir ni marcar ----
        ciclo_nucleo(1'b0, 1'b1, 1'b1, 32'h0000_0010, 4'b1111, 32'hBAD0_0001);  // enable = 0
        ciclo_nucleo(1'b1, 1'b1, 1'b0, 32'h0000_0014, 4'b1111, 32'hBAD0_0002);  // valid = 0
        ciclo_nucleo(1'b1, 1'b0, 1'b1, 32'h0000_0018, 4'b1111, 32'hBAD0_0003);  // we = 0
        ciclo_nucleo(1'b0, 1'b1, 1'b0, 32'h0000_001C, 4'b1111, 32'hBAD0_0004);  // los dos en 0
        comparar_todo("AC2 store sin enable/valid");

        // ---- Escritura por byte (i_be) ----
        store(32'h0000_0020, 4'b1111, 32'h1122_3344);  // sw en la palabra 8
        store(32'h0000_0024, 4'b0001, 32'h0000_00AA);  // sb byte 0 de la palabra 9
        store(32'h0000_0024, 4'b0100, 32'h00BB_0000);  // sb byte 2
        store(32'h0000_0028, 4'b0010, 32'h0000_CC00);  // sb byte 1 de la palabra 10
        store(32'h0000_0028, 4'b1000, 32'hDD00_0000);  // sb byte 3
        store(32'h0000_002C, 4'b0011, 32'h0000_EEFF);  // sh mitad baja de la palabra 11
        store(32'h0000_002C, 4'b1100, 32'h1357_0000);  // sh mitad alta
        store(32'h0000_0020, 4'b0010, 32'hFFFF_FFFF);  // sb sobre el sw: solo cambia [15:8]
        comparar_todo("escritura por byte");
        check_eq("sw + sb en la palabra 8", r_modelo[8], 32'h1122_FF44);

        // ---- Lectura combinacional del puerto del nucleo ----
        r_addr = 32'h0000_0020;
        #1 check_eq("o_rdata palabra 8", w_rdata, 32'h1122_FF44);
        r_addr = 32'h0000_002E;  // los bits bajos se ignoran
        #1 check_eq("o_rdata 0x2E lee la palabra 11", w_rdata, 32'h1357_EEFF);
        r_addr = BYTES_DMEM + 32'h0000_0024;  // da la vuelta
        #1 check_eq("o_rdata 0x424 lee la palabra 9", w_rdata, 32'h00BB_00AA);

        // ---- AC3: el bitmap marca exactamente las palabras escritas ----
        // Hasta aca se escribieron las palabras 8, 9, 10 y 11 (varias veces cada una).
        check_eq("AC3 contador = 4", {23'd0, w_used_count}, 32'd4);
        store(32'h0000_0020, 4'b1111, 32'hCAFE_0008);  // la 8 otra vez: el contador no sube
        check_eq("AC3 reescritura no cuenta", {23'd0, w_used_count}, 32'd4);
        store(BYTES_DMEM + 32'h0000_0020, 4'b1111, 32'hCAFE_0408);  // 0x420 = palabra 8
        check_eq("AC3 0x420 es la palabra 8", {23'd0, w_used_count}, 32'd4);
        store(32'h0000_03FC, 4'b1000, 32'h7700_0000);  // ultima palabra (255)
        store(32'h0000_0000, 4'b0001, 32'h0000_0001);  // primera palabra (0)
        comparar_todo("AC3 bitmap");

        // ---- AC4: la limpieza de la Debug Unit escribe ceros y no toca el bitmap ----
        limpiar_du(8);  // palabra marcada: queda marcada
        limpiar_du(9);
        limpiar_du(100);  // palabra sin marcar: sigue sin marcar
        comparar_todo("AC4 limpieza sin marcar");

        // La limpieza le gana al store del mismo ciclo: el store no escribe ni marca.
        r_dbg_we      = 1'b1;
        r_dbg_wr_addr = 50;
        r_enable      = 1'b1;
        r_we          = 1'b1;
        r_valid       = 1'b1;
        r_addr        = 32'h0000_00C8;  // palabra 50
        r_be          = 4'b1111;
        r_wdata       = 32'hBAD0_0050;
        @(posedge clock);
        r_modelo[50] = 32'h0000_0000;
        @(negedge clock);
        r_dbg_we = 1'b0;
        r_enable = 1'b0;
        r_we     = 1'b0;
        r_valid  = 1'b0;
        comparar_todo("limpieza vs store simultaneo");

        // ---- AC3: i_clear_used limpia bitmap y contador, pero no los datos ----
        borrar_usadas;
        comparar_todo("AC3 i_clear_used");
        check_eq("los datos siguen (palabra 11)", r_modelo[11], 32'h1357_EEFF);

        // i_clear_used le gana al store del mismo ciclo en el bitmap (el dato si se escribe).
        r_clear_used = 1'b1;
        r_enable     = 1'b1;
        r_we         = 1'b1;
        r_valid      = 1'b1;
        r_addr       = 32'h0000_0030;  // palabra 12
        r_be         = 4'b1111;
        r_wdata      = 32'h0000_0C0C;
        @(posedge clock);
        r_modelo[12] = 32'h0000_0C0C;
        @(negedge clock);
        r_clear_used = 1'b0;
        r_enable     = 1'b0;
        r_we         = 1'b0;
        r_valid      = 1'b0;
        comparar_todo("clear_used vs store simultaneo");

        // i_clear_used no depende de i_enable (ya esta en 0).
        store(32'h0000_0034, 4'b1111, 32'h0000_0D0D);
        check_eq("antes de borrar: 1 usada", {23'd0, w_used_count}, 32'd1);
        borrar_usadas;
        check_eq("i_clear_used con enable = 0", {23'd0, w_used_count}, 32'd0);

        // ---- Las 256 palabras usadas: el contador llega a 256 (9 bits) ----
        for (k = 0; k < DEPTH; k = k + 1) store(4 * k, 4'b1111, 32'hA000_0000 + k);
        comparar_todo("256 palabras usadas");
        check_eq("contador = 256", {23'd0, w_used_count}, 32'd256);

        // ---- AC5: con el nucleo congelado la Debug Unit lee cualquier palabra ----
        // El puerto del nucleo y el de la Debug Unit leen direcciones distintas a la vez.
        r_enable   = 1'b0;
        r_addr     = 32'h0000_0040;  // palabra 16
        r_dbg_addr = 200;
        #1;
        check_eq("AC5 nucleo lee la 16", w_rdata, 32'hA000_0010);
        check_eq("AC5 Debug Unit lee la 200", w_dbg_data, 32'hA000_00C8);
        check_eq("AC5 bit usado de la 200", {31'd0, w_dbg_used}, 32'd1);
        repeat (5) @(posedge clock);
        @(negedge clock);
        comparar_todo("AC5 congelado 5 ciclos");

        tb_finish;
    end
endmodule
