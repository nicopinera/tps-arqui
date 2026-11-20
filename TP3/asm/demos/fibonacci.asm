# Fibonacci iterativo (US-410, demo): guarda F(0) … F(11) en la DMEM desde 0x000.
# Esperado: [0x000..0x02C] = 0 1 1 2 3 5 8 13 21 34 55 89; x1 = F(12) = 144, x2 = F(13) = 233.
        addi x1, x0, 0          # a = F(n)
        addi x2, x0, 1          # b = F(n+1)
        addi x3, x0, 0          # puntero a la DMEM
        addi x4, x0, 12         # términos que faltan guardar
loop:
        sw   x1, 0(x3)          # [x3] = a
        add  x5, x1, x2         # siguiente = a + b
        addi x1, x2, 0          # a = b
        addi x2, x5, 0          # b = siguiente
        addi x3, x3, 4
        addi x4, x4, -1
        bne  x4, x0, loop       # 12 vueltas
        halt
