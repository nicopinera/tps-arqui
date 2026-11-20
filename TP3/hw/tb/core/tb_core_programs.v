`timescale 1ns / 1ps

// Testbench de sistema del nucleo: corre un programa y compara el estado final con el golden
// model (US-210, AC1 a AC4).
//
// Plusargs:
//   +HEX=<ruta>         programa ensamblado (rvasm, una palabra por linea). Obligatorio.
//   +EXPECTED=<ruta>    estado final del golden model (rvsim --expect). Obligatorio.
//   +MAX_CICLOS=<n>     limite de ciclos con enable (por defecto 10000).
//   +ENABLE_ALEATORIO   i_enable alterna al azar entre 0 y 1 (AC4).
//   +SEMILLA=<n>        semilla del enable aleatorio (por defecto 210).
// make sim-programs los arma para cada programa de asm/tests/h2.
//
// Secuencia, como la de un LOAD de la Debug Unit (ADR-009):
// 1. Con i_enable = 0: escribe la IMEM por i_imem_we (lo que no ocupa el programa se rellena
//    con HALT), limpia la DMEM por i_dbg_dmem_we y borra el bitmap.
// 2. Pulso de i_flush_all.
// 3. Corre hasta o_halted (o el limite de ciclos).
// 4. Compara contra el .expected:
//    - motivo (o_illegal) y PC: el PC queda congelado en la instruccion siguiente al HALT o a
//      la ilegal, porque la busqueda se detiene cuando el HALT esta en ID;
//    - x1..x31 por el puerto de depuracion del banco;
//    - memoria usada: la cantidad (o_dbg_used_count) y cada palabra con su bit de usada.
//    - AC2: los 4 bits valid de los buses de latches en 0.
//
// Ademas, en cada ciclo se verifica AC3: despues de que un HALT valido entra a EX, ninguna otra
// instruccion valida entra a EX.
module tb_core_programs;
    `include "tb_utils.vh"

    localparam PERIODO = 10;
    localparam IMEM_DEPTH = 256;
    localparam DMEM_DEPTH = 256;
    localparam ADDR_BITS = 8;
    localparam MAX_CICLOS_DEF = 10000;
    localparam SEMILLA_DEF = 210;
    localparam [31:0] HALT_WORD = 32'h0000_000B;

    // .expected: motivo, PC, x0..x31, K y K pares direccion/dato (iss/expected.py)
    localparam EXP_MOTIVO = 0;
    localparam EXP_PC = 1;
    localparam EXP_REGS = 2;
    localparam EXP_K = 34;
    localparam EXP_PARES = 35;
    localparam EXP_MAX = EXP_PARES + 2 * DMEM_DEPTH;
    localparam [31:0] MOTIVO_HALTED = 32'd1;
    localparam [31:0] MOTIVO_ILLEGAL = 32'd2;

    // Bits valid, halt y pc en los buses de latches (riscv_core.md 4)
    localparam IF_ID_VALID = 96;
    localparam ID_EX_VALID = 200;
    localparam EX_MEM_VALID = 112;
    localparam MEM_WB_VALID = 104;

    reg                  clock = 1'b0;
    reg                  r_reset = 1'b1;
    reg                  r_enable = 1'b0;
    reg                  r_flush_all = 1'b0;
    reg                  r_stop_fetch = 1'b0;
    reg                  r_imem_we = 1'b0;
    reg  [ADDR_BITS-1:0] r_imem_addr = 0;
    reg  [         31:0] r_imem_wdata = 0;
    reg                  r_dbg_dmem_we = 1'b0;
    reg  [ADDR_BITS-1:0] r_dbg_dmem_addr = 0;
    reg                  r_clear_used = 1'b0;
    reg  [          4:0] r_dbg_reg_addr = 0;
    reg  [ADDR_BITS-1:0] r_dbg_mem_addr = 0;

    wire                 w_halted;
    wire                 w_illegal;
    wire [         31:0] w_pc;
    wire [         31:0] w_dbg_reg_data;
    wire [         31:0] w_dbg_mem_data;
    wire                 w_dbg_mem_used;
    wire [  ADDR_BITS:0] w_dbg_used_count;
    wire [        103:0] w_if_id;
    wire [        247:0] w_id_ex;
    wire [        151:0] w_ex_mem;
    wire [        143:0] w_mem_wb;

    reg  [         31:0] r_programa       [0:IMEM_DEPTH-1];
    reg  [         31:0] r_esperado       [  0:EXP_MAX-1];
    reg  [       1023:0] r_hex;
    reg  [       1023:0] r_expected;
    integer              max_ciclos;
    integer              semilla;
    reg                  r_aleatorio;

    // AC3: PC del HALT que entro a EX
    reg                  r_halt_en_ex = 1'b0;
    reg  [         31:0] r_pc_halt;

    integer              k;
    integer              ciclos;
    integer              ciclos_con_enable;

    riscv_core #(
        .IMEM_DEPTH (IMEM_DEPTH),
        .DMEM_DEPTH (DMEM_DEPTH),
        .DEBUG_TRACE(1)
    ) u_core (
        .clock           (clock),
        .i_reset         (r_reset),
        .i_enable        (r_enable),
        .i_flush_all     (r_flush_all),
        .i_stop_fetch    (r_stop_fetch),
        .o_halted        (w_halted),
        .o_illegal       (w_illegal),
        .o_pc            (w_pc),
        .i_imem_we       (r_imem_we),
        .i_imem_addr     (r_imem_addr),
        .i_imem_wdata    (r_imem_wdata),
        .i_dbg_dmem_we   (r_dbg_dmem_we),
        .i_dbg_dmem_addr (r_dbg_dmem_addr),
        .i_clear_used    (r_clear_used),
        .i_dbg_reg_addr  (r_dbg_reg_addr),
        .o_dbg_reg_data  (w_dbg_reg_data),
        .i_dbg_mem_addr  (r_dbg_mem_addr),
        .o_dbg_mem_data  (w_dbg_mem_data),
        .o_dbg_mem_used  (w_dbg_mem_used),
        .o_dbg_used_count(w_dbg_used_count),
        .o_stall         (),
        .o_flush_if_id   (),
        .o_flush_id_ex   (),
        .o_fwd_a         (),
        .o_fwd_b         (),
        .o_if_id         (w_if_id),
        .o_id_ex         (w_id_ex),
        .o_ex_mem        (w_ex_mem),
        .o_mem_wb        (w_mem_wb)
    );

    always #(PERIODO / 2) clock = ~clock;

    // AC3: se mira lo que entro a ID/EX en cada flanco con el nucleo habilitado
    always @(posedge clock) begin
        #1;
        if (!r_reset && !r_flush_all && w_id_ex[ID_EX_VALID]) begin
            if (r_halt_en_ex && w_id_ex[31:0] != r_pc_halt) begin
                $display("  [FALLA] AC3: entro a EX la instruccion de 0x%08h despues del HALT de 0x%08h",
                         w_id_ex[31:0], r_pc_halt);
                tb_errors = tb_errors + 1;
            end
            if (!r_halt_en_ex && w_id_ex[208]) begin  // halt
                r_halt_en_ex = 1'b1;
                r_pc_halt    = w_id_ex[31:0];
            end
        end
    end

    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    initial begin
        tb_init;

        if (!$value$plusargs("HEX=%s", r_hex) || !$value$plusargs("EXPECTED=%s", r_expected)) begin
            $display("Uso: +HEX=<programa.hex> +EXPECTED=<programa.expected> (ver make sim-programs)");
            tb_errors = tb_errors + 1;
            tb_finish;
        end
        if (!$value$plusargs("MAX_CICLOS=%d", max_ciclos)) max_ciclos = MAX_CICLOS_DEF;
        if (!$value$plusargs("SEMILLA=%d", semilla)) semilla = SEMILLA_DEF;
        r_aleatorio = $test$plusargs("ENABLE_ALEATORIO");

        for (k = 0; k < IMEM_DEPTH; k = k + 1) r_programa[k] = HALT_WORD;
        for (k = 0; k < EXP_MAX; k = k + 1) r_esperado[k] = 32'h0;
        $readmemh(r_hex, r_programa);
        $readmemh(r_expected, r_esperado);
        $display("Programa: %0s%0s", r_hex, r_aleatorio ? "  (enable aleatorio)" : "");

        // ---- 1. Carga como un LOAD, con el nucleo congelado ----
        @(negedge clock);
        r_imem_we     = 1'b1;
        r_dbg_dmem_we = 1'b1;
        r_clear_used  = 1'b1;
        for (k = 0; k < IMEM_DEPTH; k = k + 1) begin
            r_imem_addr     = k[ADDR_BITS-1:0];
            r_imem_wdata    = r_programa[k];
            r_dbg_dmem_addr = k[ADDR_BITS-1:0];
            ciclo;
        end
        r_imem_we     = 1'b0;
        r_dbg_dmem_we = 1'b0;
        r_clear_used  = 1'b0;
        r_reset       = 1'b0;

        // ---- 2. Flush global ----
        r_flush_all = 1'b1;
        ciclo;
        r_flush_all = 1'b0;

        // ---- 3. Corre hasta o_halted ----
        ciclos            = 0;
        ciclos_con_enable = 0;
        while (!w_halted && ciclos_con_enable < max_ciclos) begin
            r_enable = r_aleatorio ? $random(semilla) : 1'b1;
            if (r_enable) ciclos_con_enable = ciclos_con_enable + 1;
            ciclos = ciclos + 1;
            ciclo;
        end
        r_enable = 1'b0;
        $display("Termino en %0d ciclos (%0d con enable)", ciclos, ciclos_con_enable);

        // ---- 4. Comparacion con el golden model ----
        check_eq("termina (o_halted)", {31'd0, w_halted}, 32'd1);
        check_eq("motivo (o_illegal)", {31'd0, w_illegal},
                 {31'd0, r_esperado[EXP_MOTIVO] == MOTIVO_ILLEGAL});
        check_eq("PC = el del HALT + 4", w_pc, r_esperado[EXP_PC] + 32'd4);

        // AC2: pipeline vacio
        check_eq("AC2 IF/ID vacio", {31'd0, w_if_id[IF_ID_VALID]}, 32'd0);
        check_eq("AC2 ID/EX vacio", {31'd0, w_id_ex[ID_EX_VALID]}, 32'd0);
        check_eq("AC2 EX/MEM vacio", {31'd0, w_ex_mem[EX_MEM_VALID]}, 32'd0);
        check_eq("AC2 MEM/WB vacio", {31'd0, w_mem_wb[MEM_WB_VALID]}, 32'd0);

        // Registros
        for (k = 1; k < 32; k = k + 1) begin
            r_dbg_reg_addr = k[4:0];
            #1;
            if (w_dbg_reg_data !== r_esperado[EXP_REGS+k])
                $display("  x%0d = 0x%08h, golden model 0x%08h", k, w_dbg_reg_data,
                         r_esperado[EXP_REGS+k]);
            check_eq("registro", w_dbg_reg_data, r_esperado[EXP_REGS+k]);
        end

        // Memoria usada: cantidad y cada palabra (la direccion del .expected es de byte)
        check_eq("palabras usadas", {23'd0, w_dbg_used_count}, r_esperado[EXP_K]);
        for (k = 0; k < r_esperado[EXP_K]; k = k + 1) begin
            r_dbg_mem_addr = r_esperado[EXP_PARES+2*k][ADDR_BITS+1:2];
            #1;
            if (w_dbg_mem_data !== r_esperado[EXP_PARES+2*k+1] || !w_dbg_mem_used)
                $display("  [0x%03h] = 0x%08h (usada %0d), golden model 0x%08h",
                         r_esperado[EXP_PARES+2*k], w_dbg_mem_data, w_dbg_mem_used,
                         r_esperado[EXP_PARES+2*k+1]);
            check_eq("memoria: dato", w_dbg_mem_data, r_esperado[EXP_PARES+2*k+1]);
            check_eq("memoria: usada", {31'd0, w_dbg_mem_used}, 32'd1);
        end

        tb_finish;
    end
endmodule
