# Doble coincidencia: las dos instrucciones anteriores escriben el mismo registro; tiene que
# llegar la mas reciente (EX/MEM gana a MEM/WB) (US-301 AC3).
# Casos: 2: x2 = 2 (no 1) · 3: x3 = 10 · 4: x4 = 20 · 5: x6 = 3 (el ultimo de tres)
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

# caso 2
        addi x31, x0, 2
        addi x29, x0, 2
        bne  x2, x29, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 10
        bne  x3, x29, falla
# caso 4
        addi x31, x0, 4
        addi x29, x0, 20
        bne  x4, x29, falla
# caso 5
        addi x31, x0, 5
        addi x29, x0, 3
        bne  x6, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
