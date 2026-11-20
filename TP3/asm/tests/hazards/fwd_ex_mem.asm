# Forwarding desde EX/MEM: la instruccion siguiente usa el resultado (US-301 AC1).
# Sin nop: cada instruccion depende de la inmediatamente anterior.
# Casos: 2: x2 = 20 · 3: x3 = 10 · 4: x4 = 40 · 5: x5 = ~40 · 6: x6 = 0 · 7: x7 = ~40
#        8: x8 = -40 · 9: x9 = -1 · 10: x10 = -2
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

# caso 2
        addi x31, x0, 2
        addi x29, x0, 20
        bne  x2, x29, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 10
        bne  x3, x29, falla
# caso 4
        addi x31, x0, 4
        addi x29, x0, 40
        bne  x4, x29, falla
# caso 5
        addi x31, x0, 5
        addi x29, x0, -41       # ~40
        bne  x5, x29, falla
# caso 6
        addi x31, x0, 6
        bne  x6, x0, falla
# caso 7
        addi x31, x0, 7
        addi x29, x0, -41       # ~40
        bne  x7, x29, falla
# caso 8
        addi x31, x0, 8
        addi x29, x0, -40
        bne  x8, x29, falla
# caso 9
        addi x31, x0, 9
        addi x29, x0, -1
        bne  x9, x29, falla
# caso 10
        addi x31, x0, 10
        addi x29, x0, -2
        bne  x10, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
