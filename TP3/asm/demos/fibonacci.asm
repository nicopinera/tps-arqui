# Fibonacci iterativo: guarda F(0) a F(19) en 0x100 .. 0x14c (demo).
# Resultado: [0x14c] = x2 = F(19) = 4181.
        addi x10, x0, 0x100     # puntero
        addi x11, x0, 20        # terminos que faltan
        addi x1, x0, 0          # F(n)
        addi x2, x0, 1          # F(n + 1)
lazo:
        sw   x1, 0(x10)
        add  x3, x1, x2         # F(n + 2)
        addi x1, x2, 0
        addi x2, x3, 0
        addi x10, x10, 4
        addi x11, x11, -1
        bne  x11, x0, lazo
        lw   x2, -4(x10)        # el ultimo guardado: F(19) = 4181
        halt
