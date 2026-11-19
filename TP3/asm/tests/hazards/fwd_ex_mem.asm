# Forwarding desde EX/MEM: la instruccion siguiente usa el resultado (US-301 AC1).
# Sin nop: cada instruccion depende de la inmediatamente anterior.
        addi x1, x0, 10         # x1 = 10
        add  x2, x1, x1         # 20: rs1 y rs2 desde EX/MEM
        sub  x3, x2, x1         # 10: rs1 desde EX/MEM, rs2 desde MEM/WB
        slli x4, x3, 2          # 40
        xori x5, x4, -1         # ~40
        and  x6, x5, x4         # 0
        or   x7, x6, x5         # ~40
        addi x8, x7, 1          # -40
        sra  x9, x8, x1         # -40 >> 10 = -1
        add  x10, x9, x9        # -2
        halt
