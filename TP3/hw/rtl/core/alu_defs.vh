// Constantes de la ALU y de su control (US-201, ADR-019).
//
// Se incluye DENTRO del cuerpo de cada modulo que las usa (alu.v, alu_control.v y, mas adelante,
// control_unit.v), asi los localparam quedan locales a ese modulo:
//
//   module alu #(...) (...);
//     `include "alu_defs.vh"
//     ...
//
// No lleva guarda `ifndef: con guarda, el segundo modulo que lo incluye en la misma compilacion
// se quedaria sin las constantes.
//
// Cada modulo usa solo una parte de las constantes; se apaga UNUSEDPARAM de Verilator para que
// el lint no avise por las que ese modulo no usa.

/* verilator lint_off UNUSEDPARAM */

// ---------------------------------------------------------------------------------------------
// alu_ctrl[3:0]: operacion interna de la ALU.
// Se codifica como {funct7_b5, funct3} de la instruccion R equivalente, para que en las ondas
// se lea igual que la ISA. PASS_B no existe en la ISA: usa 1111, que ninguna instruccion R usa.
// ---------------------------------------------------------------------------------------------
localparam [3:0] ALU_ADD    = 4'b0000; // a + b
localparam [3:0] ALU_SLL    = 4'b0001; // a << b[4:0]
localparam [3:0] ALU_SLT    = 4'b0010; // $signed(a) < $signed(b)
localparam [3:0] ALU_SLTU   = 4'b0011; // a < b (sin signo)
localparam [3:0] ALU_XOR    = 4'b0100; // a ^ b
localparam [3:0] ALU_SRL    = 4'b0101; // a >> b[4:0]
localparam [3:0] ALU_OR     = 4'b0110; // a | b
localparam [3:0] ALU_AND    = 4'b0111; // a & b
localparam [3:0] ALU_SUB    = 4'b1000; // a - b
localparam [3:0] ALU_SRA    = 4'b1101; // $signed(a) >>> b[4:0]
localparam [3:0] ALU_PASS_B = 4'b1111; // b (lui: el inmediato ya viene desplazado)

// ---------------------------------------------------------------------------------------------
// alu_op[1:0]: lo genera la unidad de control en ID (tabla_control.md, seccion 2).
// ---------------------------------------------------------------------------------------------
localparam [1:0] ALU_OP_ADD    = 2'b00; // loads, stores, jalr
localparam [1:0] ALU_OP_PASS_B = 2'b01; // lui
localparam [1:0] ALU_OP_R      = 2'b10; // R-type: funct3 + funct7_b5
localparam [1:0] ALU_OP_I      = 2'b11; // I aritmetico: funct3 (funct7_b5 solo si funct3 = 101)

// ---------------------------------------------------------------------------------------------
// funct3 de las instrucciones R e I aritmeticas.
// ---------------------------------------------------------------------------------------------
localparam [2:0] F3_ADD_SUB = 3'b000; // add/sub/addi
localparam [2:0] F3_SLL     = 3'b001; // sll/slli
localparam [2:0] F3_SLT     = 3'b010; // slt/slti
localparam [2:0] F3_SLTU    = 3'b011; // sltu/sltiu
localparam [2:0] F3_XOR     = 3'b100; // xor/xori
localparam [2:0] F3_SR      = 3'b101; // srl/sra/srli/srai
localparam [2:0] F3_OR      = 3'b110; // or/ori
localparam [2:0] F3_AND     = 3'b111; // and/andi

/* verilator lint_on UNUSEDPARAM */
