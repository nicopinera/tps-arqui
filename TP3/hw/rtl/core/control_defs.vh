// Constantes de la unidad de control y del generador de inmediatos.
// Valores documentados en docs/interfaces/tabla_control.md (secciones 1 y 3).
//
// Mismo esquema que alu_defs.vh: se incluye DENTRO del cuerpo de cada modulo, no lleva guarda
// `ifndef y apaga UNUSEDPARAM porque cada modulo usa solo una parte.
//
// El opcode de HALT sale de du_defs.vh, que se genera desde isa/instrucciones.py: asi hardware
// y software comparten una sola fuente.

`include "du_defs.vh"

/* verilator lint_off UNUSEDPARAM */

// ---------------------------------------------------------------------------------------------
// opcode (instr[6:0]) de las instrucciones implementadas (PRD 2.2)
// ---------------------------------------------------------------------------------------------
localparam [6:0] OP_R      = 7'b0110011;  // add, sub, sll, ...
localparam [6:0] OP_I_ARIT = 7'b0010011;  // addi, slti, ..., slli, srli, srai
localparam [6:0] OP_LOAD   = 7'b0000011;  // lb, lh, lw, lbu, lhu
localparam [6:0] OP_STORE  = 7'b0100011;  // sb, sh, sw
localparam [6:0] OP_BRANCH = 7'b1100011;  // beq, bne
localparam [6:0] OP_JALR   = 7'b1100111;
localparam [6:0] OP_LUI    = 7'b0110111;
localparam [6:0] OP_JAL    = 7'b1101111;
localparam [6:0] OP_HALT   = `DU_HALT_OPCODE;  // custom-0, 0001011

// ---------------------------------------------------------------------------------------------
// funct7 (instr[31:25]) legales en R y en los shifts inmediatos
// ---------------------------------------------------------------------------------------------
localparam [6:0] F7_BASE = 7'b0000000;  // add, srl, slli, srli, ...
localparam [6:0] F7_ALT  = 7'b0100000;  // sub, sra, srai

// ---------------------------------------------------------------------------------------------
// funct3 de loads, stores, branches y jalr (los de R/I estan en alu_defs.vh)
// ---------------------------------------------------------------------------------------------
localparam [2:0] F3_LB   = 3'b000;
localparam [2:0] F3_LH   = 3'b001;
localparam [2:0] F3_LW   = 3'b010;
localparam [2:0] F3_LBU  = 3'b100;
localparam [2:0] F3_LHU  = 3'b101;
localparam [2:0] F3_SB   = 3'b000;
localparam [2:0] F3_SH   = 3'b001;
localparam [2:0] F3_SW   = 3'b010;
localparam [2:0] F3_BEQ  = 3'b000;
localparam [2:0] F3_BNE  = 3'b001;
localparam [2:0] F3_JALR = 3'b000;

// ---------------------------------------------------------------------------------------------
// result_src[1:0]: que escribe WB en rd
// ---------------------------------------------------------------------------------------------
localparam [1:0] RES_ALU = 2'b00;  // resultado de la ALU
localparam [1:0] RES_MEM = 2'b01;  // dato leido de DMEM (loads)
localparam [1:0] RES_PC4 = 2'b10;  // PC + 4 (jal, jalr)

// ---------------------------------------------------------------------------------------------
// imm_type[2:0]: formato del inmediato que arma imm_gen
// ---------------------------------------------------------------------------------------------
localparam [2:0] IMM_I = 3'b000;
localparam [2:0] IMM_S = 3'b001;
localparam [2:0] IMM_B = 3'b010;
localparam [2:0] IMM_U = 3'b011;
localparam [2:0] IMM_J = 3'b100;

// ---------------------------------------------------------------------------------------------
// Burbuja: instr que queda en un latch con valid = 0 (flush, halt_fetch o reset)
// ---------------------------------------------------------------------------------------------
localparam [31:0] INSTR_NOP = 32'h0000_0013;  // addi x0, x0, 0

/* verilator lint_on UNUSEDPARAM */
