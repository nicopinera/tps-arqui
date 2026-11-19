# Doble coincidencia: las dos instrucciones anteriores escriben el mismo registro; tiene que
# llegar la mas reciente (EX/MEM gana a MEM/WB) (US-301 AC3).
        addi x1, x0, 1          # x1 = 1 (viejo)
        addi x1, x0, 2          # x1 = 2 (nuevo)
        add  x2, x1, x0         # 2, no 1
        addi x3, x0, 5
        addi x3, x3, 5          # 10: usa el 5 desde EX/MEM y escribe x3
        add  x4, x3, x3         # 20: los dos operandos desde EX/MEM
        addi x5, x0, -1
        addi x5, x0, -2
        addi x5, x0, -3
        sub  x6, x0, x5         # 3: el ultimo de tres
        halt
