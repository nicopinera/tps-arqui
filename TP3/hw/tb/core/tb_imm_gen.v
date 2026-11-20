`timescale 1ns / 1ps

// Testbench del generador de inmediatos.
//
// Lee los vectores que genera tools/scripts/gen_imm_vectors.py (instrucciones ensambladas por
// el ensamblador del proyecto e inmediatos esperados calculados con isa/formatos.py) y compara
// la salida de imm_gen con cada uno.
//
// Para regenerar los vectores (desde TP3/tools/):  uv run python -m scripts.gen_imm_vectors
// Se pueden pasar otros archivos con +HEX=<instrucciones> +ESPERADO=<esperados>.
module tb_imm_gen;
    `include "tb_utils.vh"

    localparam MAX_VECTORES = 256;
    localparam IMM_TYPE_BITS = 3;
    localparam NBIT = 32;
    localparam IMM_TYPE_SIN_USO = 3'b111;  // ningun formato: imm = 0

    reg     [         NBIT-1:0] r_instr;
    reg     [IMM_TYPE_BITS-1:0] r_imm_type;
    wire    [         NBIT-1:0] w_imm;

    // Cada esperado es {imm_type (un digito hex: 4 bits, el de arriba en 0), inmediato (32 bits)}.
    reg     [         NBIT-1:0] r_instrucciones [0:MAX_VECTORES-1];
    reg     [         NBIT+3:0] r_esperados     [0:MAX_VECTORES-1];
    reg     [           1023:0] r_ruta_hex;
    reg     [           1023:0] r_ruta_esperado;

    integer                     k;
    integer                     n_vectores;

    imm_gen u_imm_gen (
        .i_instr   (r_instr),
        .i_imm_type(r_imm_type),
        .o_imm     (w_imm)
    );

    initial begin
        tb_init;

        if (!$value$plusargs("HEX=%s", r_ruta_hex)) r_ruta_hex = "hw/tb/core/vectores/imm_gen.hex";
        if (!$value$plusargs("ESPERADO=%s", r_ruta_esperado)) r_ruta_esperado = "hw/tb/core/vectores/imm_gen_esperado.hex";

        // Las posiciones que el archivo no llena quedan en X: marcan el final.
        for (k = 0; k < MAX_VECTORES; k = k + 1) r_esperados[k] = {(NBIT + 4) {1'bx}};
        $readmemh(r_ruta_hex, r_instrucciones);
        $readmemh(r_ruta_esperado, r_esperados);

        n_vectores = 0;
        for (k = 0; k < MAX_VECTORES; k = k + 1) begin
            if (r_esperados[k][0] !== 1'bx) begin
                r_instr    = r_instrucciones[k];
                r_imm_type = r_esperados[k][NBIT+IMM_TYPE_BITS-1:NBIT];
                #1;
                if (w_imm !== r_esperados[k][NBIT-1:0]) $display("  vector %0d: instr = 0x%08h, imm_type = %b", k, r_instr, r_imm_type);
                check_eq("imm_gen vs formatos.py", w_imm, r_esperados[k][NBIT-1:0]);
                n_vectores = n_vectores + 1;
            end
        end
        $display("  %0d vectores leidos de %0s", n_vectores, r_ruta_esperado);
        check_eq("al menos 50 vectores", {31'd0, n_vectores >= 50}, 32'd1);

        // imm_type sin formato asignado: el inmediato es 0.
        r_instr    = 32'hFFFF_FFFF;
        r_imm_type = IMM_TYPE_SIN_USO;
        #1;
        check_eq("imm_type 111 da 0", w_imm, 32'h0000_0000);

        tb_finish;
    end
endmodule
