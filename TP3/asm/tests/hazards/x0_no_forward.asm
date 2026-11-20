# Escribir x0 nunca genera forwarding: x0 vale siempre 0 (US-301 AC4).
# Casos: 2: x1 = 0 · 3: x3 = 1 · 4: [0x40] = 0 (se guardo x0 justo despues de un lui x0)
        addi x0, x0, 5          # no tiene efecto
        add  x1, x0, x0         # 0, no 10
        addi x0, x0, 7
        addi x2, x0, 1
        add  x3, x0, x2         # x0 = 0 (en MEM/WB "se escribio" 7), x2 desde EX/MEM
        lui  x0, 0x12345
        sw   x0, 0x40(x0)       # guarda 0 en 0x40

# caso 2
        addi x31, x0, 2
        bne  x1, x0, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 1
        bne  x3, x29, falla
# caso 4
        addi x31, x0, 4
        lw   x28, 0x40(x0)
        bne  x28, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
