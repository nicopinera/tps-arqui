`timescale 1ns / 1ps

// Testbench del control de la ALU (US-201, AC2 y AC3).
//
// Parte 1: barre las 64 combinaciones de alu_op / funct3 / funct7_b5 y compara contra un modelo
//          escrito fila por fila desde tabla_control.md, seccion 4.
// Parte 2: decodifica palabras reales (sacadas del ensamblador del proyecto) y verifica los
//          casos de los criterios de aceptacion: addi con el bit 30 en 1 (AC2) y srli/srai (AC3).
module tb_alu_control;
  `include "tb_utils.vh"
  `include "alu_defs.vh"

  reg  [1:0] r_alu_op;
  reg  [2:0] r_funct3;
  reg        r_funct7_b5;
  wire [3:0] w_alu_ctrl;

  integer op;
  integer f3;
  integer b5;

  alu_control u_alu_control (
    .i_alu_op(r_alu_op), .i_funct3(r_funct3), .i_funct7_b5(r_funct7_b5),
    .o_alu_ctrl(w_alu_ctrl)
  );

  // Modelo de referencia: tabla_control.md, seccion 4.
  function [3:0] esperado;
    input [1:0] alu_op;
    input [2:0] funct3;
    input       funct7_b5;
    begin
      if (alu_op == ALU_OP_ADD)
        esperado = ALU_ADD;
      else if (alu_op == ALU_OP_PASS_B)
        esperado = ALU_PASS_B;
      else
        case (funct3)
          3'b000:  esperado = (alu_op == ALU_OP_R && funct7_b5) ? ALU_SUB : ALU_ADD;
          3'b001:  esperado = ALU_SLL;
          3'b010:  esperado = ALU_SLT;
          3'b011:  esperado = ALU_SLTU;
          3'b100:  esperado = ALU_XOR;
          3'b101:  esperado = funct7_b5 ? ALU_SRA : ALU_SRL;
          3'b110:  esperado = ALU_OR;
          default: esperado = ALU_AND;
        endcase
    end
  endfunction

  // Toma alu_op de la unidad de control y funct3/funct7_b5 de la palabra, como en EX.
  task probar_instr;
    input [255:0] nombre;   // hasta 32 caracteres
    input [1:0]   alu_op;
    input [31:0]  instr;
    input [3:0]   ctrl_esperado;
    begin
      r_alu_op    = alu_op;
      r_funct3    = instr[14:12];
      r_funct7_b5 = instr[30];
      #1;
      check_eq(nombre, {28'd0, w_alu_ctrl}, {28'd0, ctrl_esperado});
    end
  endtask

  initial
  begin
    tb_init;

    // ---- Parte 1: las 64 combinaciones ----
    for (op = 0; op < 4; op = op + 1)
      for (f3 = 0; f3 < 8; f3 = f3 + 1)
        for (b5 = 0; b5 < 2; b5 = b5 + 1)
        begin
          r_alu_op    = op[1:0];
          r_funct3    = f3[2:0];
          r_funct7_b5 = b5[0];
          #1;
          if (w_alu_ctrl !== esperado(op[1:0], f3[2:0], b5[0]))
            $display("  alu_op=%b funct3=%b funct7_b5=%b", op[1:0], f3[2:0], b5[0]);
          check_eq("barrido alu_op/funct3/funct7_b5", {28'd0, w_alu_ctrl},
                   {28'd0, esperado(op[1:0], f3[2:0], b5[0])});
        end

    // ---- Parte 2: palabras reales (rvasm) ----
    // AC2: el inmediato -1024 (0xC00) pone el bit 30 en 1; addi tiene que seguir siendo ADD.
    probar_instr("AC2 addi x1, x0, -1024",  ALU_OP_I, 32'hC000_0093, ALU_ADD);
    probar_instr("xori x1, x1, -1 (b30=1)", ALU_OP_I, 32'hFFF0_C093, ALU_XOR);
    probar_instr("andi x1, x1, -2048",      ALU_OP_I, 32'h8000_F093, ALU_AND);
    probar_instr("add x1, x2, x3",          ALU_OP_R, 32'h0031_00B3, ALU_ADD);
    probar_instr("sub x1, x2, x3",          ALU_OP_R, 32'h4031_00B3, ALU_SUB);
    // AC3: srli y srai se distinguen por funct7_b5.
    probar_instr("AC3 srli x1, x1, 3",      ALU_OP_I, 32'h0030_D093, ALU_SRL);
    probar_instr("AC3 srai x1, x1, 3",      ALU_OP_I, 32'h4030_D093, ALU_SRA);
    probar_instr("sra x1, x2, x3",          ALU_OP_R, 32'h4031_50B3, ALU_SRA);

    tb_finish;
  end
endmodule
