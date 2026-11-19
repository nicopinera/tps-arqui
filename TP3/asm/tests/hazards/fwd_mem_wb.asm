# Forwarding desde MEM/WB: el productor esta 2 instrucciones antes (US-301 AC2).
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
        halt
