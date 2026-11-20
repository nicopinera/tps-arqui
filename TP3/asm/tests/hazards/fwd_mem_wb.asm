# Forwarding desde MEM/WB: el productor esta 2 instrucciones antes (US-301 AC2).
# Casos: 2: x3 = 7 · 3: x4 = 3 · 4: x7 = 200 · 5: x8 = 1 · 6: x12 = 55 (bypass del banco)
        addi x1, x0, 7
        addi x2, x0, 3
        add  x3, x1, x0         # x1 desde MEM/WB (x2 esta en EX/MEM y no se usa)
        sub  x4, x2, x0         # x2 desde MEM/WB
        addi x5, x0, 100
        addi x6, x0, 1
        add  x7, x5, x5         # x5 desde MEM/WB en los dos operandos
        add  x8, x0, x6         # x6 desde MEM/WB en rs2
        # A 3 de distancia ya no hay forwarding: lo resuelve el bypass del banco (WB -> ID)
        addi x9, x0, 55
        addi x10, x0, 0
        addi x11, x0, 0
        add  x12, x9, x0        # 55

# caso 2
        addi x31, x0, 2
        addi x29, x0, 7
        bne  x3, x29, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 3
        bne  x4, x29, falla
# caso 4
        addi x31, x0, 4
        addi x29, x0, 200
        bne  x7, x29, falla
# caso 5
        addi x31, x0, 5
        addi x29, x0, 1
        bne  x8, x29, falla
# caso 6
        addi x31, x0, 6
        addi x29, x0, 55
        bne  x12, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
