`timescale 1ns / 1ps

// Testbench del control del nucleo: lo que no se ve comparando el estado final de un programa
// (US-210, AC2 y AC6, y la semantica de riscv_core.md 2 y 3).
//
// Programas (palabras del ensamblador del repo):
//
//   Lazo infinito                         Fin con HALT
//   0x00       addi x1, x0, 0             0x00  addi x2, x0, 5
//   0x04 lazo: addi x1, x1, 1             0x04  nop  (x3)
//   0x08       beq  x0, x0, sig           0x10  sw   x2, 0x10(x0)
//   0x0c       addi x31, x0, 1  (nunca)   0x14  halt
//   0x10 sig:  jal  x0, lazo
//
// - Senales de riesgo: en cada ciclo del lazo, o_flush_if_id/o_flush_id_ex coinciden con el
//   jal en ID y el beq en EX; o_fwd_a/o_fwd_b coinciden con el forwarding calculado a partir de
//   los buses de los latches; o_stall = 0 (el lazo no tiene loads).
// - Layout de los buses de latches (riscv_core.md 4): campos del addi, el beq y el sw.
// - AC6 (ABORT): con i_stop_fetch = 1 el pipeline queda vacio en 3 ciclos o menos, el PC no
//   cambia y la instruccion que estaba en ID no escribe; lo que estaba en EX, MEM y WB si.
// - HALT: o_halted con el pipeline vacio (AC2); despues el nucleo no avanza aunque
//   i_enable = 1.
// - i_flush_all (con i_enable = 0): PC, latches, banco y o_halted en 0; no toca el bitmap ni
//   la DMEM. i_reset ademas borra el bitmap.
// - La IMEM se carga por i_imem_we con i_enable = 0.
// - Load-use (US-302): cantidad exacta de ciclos con o_stall = 1 en programas chicos (1 si la
//   instruccion siguiente usa el registro cargado; 0 si hay una en el medio, si no lo lee o si
//   es x0).
module tb_core_control;
    `include "tb_utils.vh"

    localparam PERIODO = 10;
    localparam ADDR_BITS = 8;
    localparam CICLOS_LAZO = 40;
    localparam CICLOS_CONGELADO = 20;
    localparam MAX_DRENADO = 3;
    localparam [31:0] HALT_WORD = 32'h0000_000B;

    // Lazo infinito
    localparam [31:0] W_ADDI0 = 32'h0000_0093;  // addi x1, x0, 0
    localparam [31:0] W_ADDI = 32'h0010_8093;  // addi x1, x1, 1
    localparam [31:0] W_BEQ = 32'h0000_0463;  // beq x0, x0, +8
    localparam [31:0] W_NUNCA = 32'h0010_0F93;  // addi x31, x0, 1
    localparam [31:0] W_JAL = 32'hFF5F_F06F;  // jal x0, -12
    // Fin con HALT
    localparam [31:0] W_ADDI5 = 32'h0050_0113;  // addi x2, x0, 5
    localparam [31:0] W_NOP = 32'h0000_0013;
    localparam [31:0] W_SW = 32'h0020_2823;  // sw x2, 0x10(x0)
    // Load-use
    localparam [31:0] W_LW_X1 = 32'h0001_2083;  // lw x1, 0(x2)
    localparam [31:0] W_ADD_X1 = 32'h0040_81B3;  // add x3, x1, x4
    localparam [31:0] W_INDEP = 32'h0010_0293;  // addi x5, x0, 1
    localparam [31:0] W_LUI_X1 = 32'h1234_50B7;  // lui x1, 0x12345
    localparam [31:0] W_SW_X1 = 32'h0011_2223;  // sw x1, 4(x2)
    localparam [31:0] W_LW_X0 = 32'h0001_2003;  // lw x0, 0(x2)
    localparam [31:0] W_ADD_X0 = 32'h0000_02B3;  // add x5, x0, x0
    localparam [31:0] W_LW_X5 = 32'h0001_2283;  // lw x5, 0(x2)
    localparam [31:0] W_ADDI_IMM5 = 32'h0051_8393;  // addi x7, x3, 5: los bits de rs2 valen 5

    // Bits de los buses (riscv_core.md 4)
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
    wire                 w_stall;
    wire                 w_flush_if_id;
    wire                 w_flush_id_ex;
    wire [          1:0] w_fwd_a;
    wire [          1:0] w_fwd_b;
    wire [        103:0] w_if_id;
    wire [        247:0] w_id_ex;
    wire [        151:0] w_ex_mem;
    wire [        143:0] w_mem_wb;

    wire [          3:0] w_valids = {
        w_if_id[IF_ID_VALID], w_id_ex[ID_EX_VALID], w_ex_mem[EX_MEM_VALID], w_mem_wb[MEM_WB_VALID]
    };

    // Copias para comparar antes/despues
    reg  [         31:0] r_antes_pc;
    reg  [        103:0] r_antes_if_id;
    reg  [        247:0] r_antes_id_ex;
    reg  [        151:0] r_antes_ex_mem;
    reg  [        143:0] r_antes_mem_wb;
    reg  [         31:0] r_x1_esperado;

    integer              k;
    integer              n_addi;
    integer              n_stalls;
    integer              ciclos;
    reg                  r_visto_beq;
    reg                  r_visto_jal;
    reg                  r_visto_addi;

    riscv_core u_core (
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
        .o_stall         (w_stall),
        .o_flush_if_id   (w_flush_if_id),
        .o_flush_id_ex   (w_flush_id_ex),
        .o_fwd_a         (w_fwd_a),
        .o_fwd_b         (w_fwd_b),
        .o_if_id         (w_if_id),
        .o_id_ex         (w_id_ex),
        .o_ex_mem        (w_ex_mem),
        .o_mem_wb        (w_mem_wb)
    );

    always #(PERIODO / 2) clock = ~clock;

    // Forwarding esperado para un registro de la instruccion en EX, leyendo rd, reg_write y
    // valid de los buses de EX/MEM y MEM/WB (riscv_core.md 4)
    function [1:0] fwd_esperado;
        input [4:0] rs;
        begin
            if (w_ex_mem[EX_MEM_VALID] && w_ex_mem[115] && w_ex_mem[100:96] != 0 && w_ex_mem[100:96] == rs)
                fwd_esperado = 2'b10;
            else if (w_mem_wb[MEM_WB_VALID] && w_mem_wb[107] && w_mem_wb[100:96] != 0 && w_mem_wb[100:96] == rs)
                fwd_esperado = 2'b01;
            else fwd_esperado = 2'b00;
        end
    endfunction

    task ciclo;
        begin
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    // Carga un programa de hasta 6 palabras por i_imem_we (el resto, HALT) con el nucleo
    // congelado, y limpia la DMEM.
    task cargar;
        input [31:0] p0, p1, p2, p3, p4, p5;
        begin
            r_enable      = 1'b0;
            r_imem_we     = 1'b1;
            r_dbg_dmem_we = 1'b1;
            for (k = 0; k < 256; k = k + 1) begin
                r_imem_addr     = k[ADDR_BITS-1:0];
                r_dbg_dmem_addr = k[ADDR_BITS-1:0];
                case (k)
                    0: r_imem_wdata = p0;
                    1: r_imem_wdata = p1;
                    2: r_imem_wdata = p2;
                    3: r_imem_wdata = p3;
                    4: r_imem_wdata = p4;
                    5: r_imem_wdata = p5;
                    default: r_imem_wdata = HALT_WORD;
                endcase
                ciclo;
            end
            r_imem_we     = 1'b0;
            r_dbg_dmem_we = 1'b0;
        end
    endtask

    // Carga un programa, lo corre hasta o_halted y verifica cuantos ciclos tuvo o_stall = 1.
    task contar_stalls;
        input [255:0] nombre;
        input [31:0] p0, p1, p2, p3;
        input integer esperado;
        begin
            cargar(p0, p1, p2, p3, HALT_WORD, HALT_WORD);
            r_flush_all = 1'b1;
            ciclo;
            r_flush_all = 1'b0;
            r_enable    = 1'b1;
            n_stalls    = 0;
            ciclos      = 0;
            while (!w_halted && ciclos < 100) begin
                #1 if (w_stall) n_stalls = n_stalls + 1;
                ciclo;
                ciclos = ciclos + 1;
            end
            r_enable = 1'b0;
            check_eq(nombre, n_stalls, esperado);
        end
    endtask

    task leer_reg;
        input [4:0] n;
        begin
            r_dbg_reg_addr = n;
            #1;
        end
    endtask

    initial begin
        tb_init;
        @(negedge clock);

        // =====================================================================================
        // Lazo infinito: senales de riesgo, layout de los buses y ABORT
        // =====================================================================================
        r_clear_used = 1'b1;
        cargar(W_ADDI0, W_ADDI, W_BEQ, W_NUNCA, W_JAL, HALT_WORD);
        r_clear_used = 1'b0;
        r_reset      = 1'b0;
        check_eq("reset: PC = 0", w_pc, 32'h0);
        check_eq("reset: pipeline vacio", {28'd0, w_valids}, 32'd0);

        r_enable     = 1'b1;
        r_visto_beq  = 1'b0;
        r_visto_jal  = 1'b0;
        r_visto_addi = 1'b0;
        for (ciclos = 0; ciclos < CICLOS_LAZO; ciclos = ciclos + 1) begin
            #1;
            // Senales de riesgo del ciclo
            check_eq("o_stall = 0 (sin loads)", {31'd0, w_stall}, 32'd0);
            check_eq("o_fwd_a segun los latches", {30'd0, w_fwd_a}, {30'd0, fwd_esperado(w_id_ex[164:160])});
            check_eq("o_fwd_b segun los latches", {30'd0, w_fwd_b}, {30'd0, fwd_esperado(w_id_ex[172:168])});
            check_eq("flush_id_ex = beq en EX", {31'd0, w_flush_id_ex},
                     {31'd0, w_id_ex[ID_EX_VALID] && w_id_ex[247:216] == W_BEQ});
            check_eq("flush_if_id = beq en EX o jal en ID", {31'd0, w_flush_if_id},
                     {31'd0, w_flush_id_ex || (w_if_id[IF_ID_VALID] && w_if_id[95:64] == W_JAL)});
            // Lo que se busca de mas despues del beq nunca entra a EX
            if (w_id_ex[ID_EX_VALID])
                check_eq("addi x31 nunca llega a EX", {31'd0, w_id_ex[247:216] == W_NUNCA}, 32'd0);

            // Layout de ID/EX con el beq (pc 0x08) y con el addi x1, x1, 1 (pc 0x04)
            if (w_id_ex[ID_EX_VALID] && w_id_ex[247:216] == W_BEQ && !r_visto_beq) begin
                r_visto_beq = 1'b1;
                check_eq("ID/EX beq: pc", w_id_ex[31:0], 32'h08);
                check_eq("ID/EX beq: pc_plus4", w_id_ex[63:32], 32'h0C);
                check_eq("ID/EX beq: imm", w_id_ex[159:128], 32'h08);
                check_eq("ID/EX beq: branch", {31'd0, w_id_ex[205]}, 32'd1);
                check_eq("ID/EX beq: reg_write", {31'd0, w_id_ex[201]}, 32'd0);
                check_eq("ID/EX beq: relleno byte 26", {29'd0, w_id_ex[215:213]}, 32'd0);
            end
            if (w_id_ex[ID_EX_VALID] && w_id_ex[247:216] == W_ADDI && !r_visto_addi) begin
                r_visto_addi = 1'b1;
                check_eq("ID/EX addi: pc", w_id_ex[31:0], 32'h04);
                check_eq("ID/EX addi: rs1", {27'd0, w_id_ex[164:160]}, 32'd1);
                check_eq("ID/EX addi: rd", {27'd0, w_id_ex[180:176]}, 32'd1);
                check_eq("ID/EX addi: imm", w_id_ex[159:128], 32'd1);
                check_eq("ID/EX addi: alu_op = 11", {30'd0, w_id_ex[193:192]}, 32'd3);
                check_eq("ID/EX addi: reg_write", {31'd0, w_id_ex[201]}, 32'd1);
                check_eq("ID/EX addi: alu_src", {31'd0, w_id_ex[204]}, 32'd1);
                check_eq("ID/EX addi: relleno rs1", {29'd0, w_id_ex[167:165]}, 32'd0);
            end
            if (w_if_id[IF_ID_VALID] && w_if_id[95:64] == W_JAL) begin
                r_visto_jal = 1'b1;
                check_eq("IF/ID jal: pc", w_if_id[31:0], 32'h10);
                check_eq("IF/ID jal: pc_plus4", w_if_id[63:32], 32'h14);
                check_eq("IF/ID: relleno", {25'd0, w_if_id[103:97]}, 32'd0);
            end
            ciclo;
        end
        check_eq("se vio el beq en EX", {31'd0, r_visto_beq}, 32'd1);
        check_eq("se vio el addi en EX", {31'd0, r_visto_addi}, 32'd1);
        check_eq("se vio el jal en ID", {31'd0, r_visto_jal}, 32'd1);

        // ---- AC6: ABORT con un addi x1, x1, 1 en ID ----
        while (!(w_if_id[IF_ID_VALID] && w_if_id[95:64] == W_ADDI)) ciclo;
        // x1 final = x1 del banco + los addi que ya estan en EX, MEM o WB (el de ID no)
        leer_reg(5'd1);
        n_addi = (w_id_ex[ID_EX_VALID] && w_id_ex[247:216] == W_ADDI) +
                 (w_ex_mem[EX_MEM_VALID] && w_ex_mem[151:120] == W_ADDI) +
                 (w_mem_wb[MEM_WB_VALID] && w_mem_wb[143:112] == W_ADDI);
        r_x1_esperado = w_dbg_reg_data + n_addi;
        r_antes_pc    = w_pc;
        r_stop_fetch  = 1'b1;
        ciclos        = 0;
        while (w_valids != 4'b0000 && ciclos < 10) begin
            ciclo;
            ciclos = ciclos + 1;
            check_eq("AC6 el PC no cambia", w_pc, r_antes_pc);
        end
        check_eq("AC6 pipeline vacio", {28'd0, w_valids}, 32'd0);
        if (ciclos > MAX_DRENADO) $display("  AC6: drenado en %0d ciclos", ciclos);
        check_eq("AC6 drenado en 3 ciclos o menos", {31'd0, ciclos <= MAX_DRENADO}, 32'd1);
        for (k = 0; k < CICLOS_CONGELADO; k = k + 1) ciclo;  // sigue vacio y quieto
        check_eq("AC6 sigue vacio", {28'd0, w_valids}, 32'd0);
        check_eq("AC6 PC quieto", w_pc, r_antes_pc);
        leer_reg(5'd1);
        check_eq("AC6 el addi de ID no escribio", w_dbg_reg_data, r_x1_esperado);
        leer_reg(5'd31);
        check_eq("AC6 x31 nunca se escribio", w_dbg_reg_data, 32'h0);
        check_eq("AC6 no termina el programa", {31'd0, w_halted}, 32'd0);
        r_stop_fetch = 1'b0;
        r_enable     = 1'b0;

        // =====================================================================================
        // Fin con HALT: pipeline vacio, nucleo congelado, i_flush_all e i_reset
        // =====================================================================================
        cargar(W_ADDI5, W_NOP, W_NOP, W_NOP, W_SW, HALT_WORD);
        r_flush_all = 1'b1;
        ciclo;
        r_flush_all = 1'b0;
        check_eq("flush_all: PC = 0", w_pc, 32'h0);
        check_eq("flush_all: pipeline vacio", {28'd0, w_valids}, 32'd0);
        leer_reg(5'd1);
        check_eq("flush_all: banco en 0", w_dbg_reg_data, 32'h0);

        r_enable = 1'b1;
        ciclos   = 0;
        while (!w_halted && ciclos < 100) begin
            #1;
            // Layout de EX/MEM con el sw
            if (w_ex_mem[EX_MEM_VALID] && w_ex_mem[151:120] == W_SW) begin
                check_eq("EX/MEM sw: alu_result", w_ex_mem[31:0], 32'h10);
                check_eq("EX/MEM sw: store_data", w_ex_mem[63:32], 32'd5);
                check_eq("EX/MEM sw: funct3", {29'd0, w_ex_mem[106:104]}, 32'd2);
                check_eq("EX/MEM sw: mem_write", {31'd0, w_ex_mem[117]}, 32'd1);
                check_eq("EX/MEM sw: reg_write", {31'd0, w_ex_mem[115]}, 32'd0);
            end
            // Layout de MEM/WB con el addi x2, x0, 5
            if (w_mem_wb[MEM_WB_VALID] && w_mem_wb[143:112] == W_ADDI5) begin
                check_eq("MEM/WB addi: alu_result", w_mem_wb[31:0], 32'd5);
                check_eq("MEM/WB addi: rd", {27'd0, w_mem_wb[100:96]}, 32'd2);
                check_eq("MEM/WB addi: reg_write", {31'd0, w_mem_wb[107]}, 32'd1);
                check_eq("MEM/WB addi: pc_plus4", w_mem_wb[95:64], 32'd4);
            end
            // HALT en WB: halt = 1 en MEM/WB
            if (w_mem_wb[MEM_WB_VALID] && w_mem_wb[143:112] == HALT_WORD)
                check_eq("MEM/WB halt: bit halt", {31'd0, w_mem_wb[105]}, 32'd1);
            ciclo;
            ciclos = ciclos + 1;
        end
        check_eq("termina con HALT", {31'd0, w_halted}, 32'd1);
        check_eq("no es ilegal", {31'd0, w_illegal}, 32'd0);
        check_eq("AC2 pipeline vacio", {28'd0, w_valids}, 32'd0);
        check_eq("PC = HALT + 4", w_pc, 32'h18);

        // Con o_halted, i_enable = 1 no cambia nada
        r_antes_pc     = w_pc;
        r_antes_if_id  = w_if_id;
        r_antes_id_ex  = w_id_ex;
        r_antes_ex_mem = w_ex_mem;
        r_antes_mem_wb = w_mem_wb;
        for (k = 0; k < CICLOS_CONGELADO; k = k + 1) ciclo;
        check_eq("halted: PC quieto", w_pc, r_antes_pc);
        check_eq("halted: IF/ID quieto", {31'd0, w_if_id == r_antes_if_id}, 32'd1);
        check_eq("halted: ID/EX quieto", {31'd0, w_id_ex == r_antes_id_ex}, 32'd1);
        check_eq("halted: EX/MEM quieto", {31'd0, w_ex_mem == r_antes_ex_mem}, 32'd1);
        check_eq("halted: MEM/WB quieto", {31'd0, w_mem_wb == r_antes_mem_wb}, 32'd1);
        check_eq("halted: sigue", {31'd0, w_halted}, 32'd1);
        // Con el pipeline vacio y la busqueda detenida nada cambiaria igual: se mira el enable
        // interno del nucleo, que tiene que estar en 0 aunque i_enable = 1
        check_eq("halted: enable interno en 0", {31'd0, u_core.w_en}, 32'd0);
        leer_reg(5'd2);
        check_eq("x2 = 5", w_dbg_reg_data, 32'd5);
        r_dbg_mem_addr = 8'd4;  // 0x10
        #1;
        check_eq("DMEM[0x10] = 5", w_dbg_mem_data, 32'd5);
        check_eq("DMEM[0x10] usada", {31'd0, w_dbg_mem_used}, 32'd1);
        check_eq("1 palabra usada", {23'd0, w_dbg_used_count}, 32'd1);

        // ---- i_flush_all con i_enable = 0: como un reset, salvo bitmap y DMEM ----
        r_enable    = 1'b0;
        r_flush_all = 1'b1;
        ciclo;
        r_flush_all = 1'b0;
        check_eq("flush_all: o_halted = 0", {31'd0, w_halted}, 32'd0);
        check_eq("flush_all: PC = 0", w_pc, 32'h0);
        check_eq("flush_all: pipeline vacio", {28'd0, w_valids}, 32'd0);
        leer_reg(5'd2);
        check_eq("flush_all: x2 = 0", w_dbg_reg_data, 32'h0);
        check_eq("flush_all: no borra el bitmap", {23'd0, w_dbg_used_count}, 32'd1);
        check_eq("flush_all: no borra la DMEM", w_dbg_mem_data, 32'd5);

        // ---- i_reset: tambien borra el bitmap ----
        r_reset = 1'b1;
        ciclo;
        r_reset = 1'b0;
        check_eq("reset: bitmap en 0", {23'd0, w_dbg_used_count}, 32'd0);
        check_eq("reset: no borra la DMEM", w_dbg_mem_data, 32'd5);

        // ---- Despues de flush_all el programa vuelve a correr desde 0 ----
        r_enable = 1'b1;
        ciclos   = 0;
        while (!w_halted && ciclos < 100) begin
            ciclo;
            ciclos = ciclos + 1;
        end
        check_eq("vuelve a terminar", {31'd0, w_halted}, 32'd1);
        leer_reg(5'd2);
        check_eq("vuelve a calcular x2", w_dbg_reg_data, 32'd5);

        // =====================================================================================
        // Load-use (US-302): ciclos de stall
        // =====================================================================================
        contar_stalls("lw x1 + add x3,x1: 1 stall", W_LW_X1, W_ADD_X1, HALT_WORD, HALT_WORD, 1);
        contar_stalls("lw + indep + add: 0 stalls", W_LW_X1, W_INDEP, W_ADD_X1, HALT_WORD, 0);
        contar_stalls("lw x1 + lui x1: 0 stalls", W_LW_X1, W_LUI_X1, HALT_WORD, HALT_WORD, 0);
        contar_stalls("lw x1 + sw x1: 1 stall", W_LW_X1, W_SW_X1, HALT_WORD, HALT_WORD, 1);
        contar_stalls("lw x0 + add x0,x0: 0 stalls", W_LW_X0, W_ADD_X0, HALT_WORD, HALT_WORD, 0);
        contar_stalls("lw x5 + addi (imm 5): 0", W_LW_X5, W_ADDI_IMM5, HALT_WORD, HALT_WORD, 0);
        contar_stalls("lw x1 + add + add: 1 stall", W_LW_X1, W_ADD_X1, W_ADD_X1, HALT_WORD, 1);

        tb_finish;
    end
endmodule
