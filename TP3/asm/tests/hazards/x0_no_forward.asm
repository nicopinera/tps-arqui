# Escribir x0 nunca genera forwarding: x0 vale siempre 0 (US-301 AC4).
        addi x0, x0, 5          # no tiene efecto
        add  x1, x0, x0         # 0, no 10
        addi x0, x0, 7
        addi x2, x0, 1
        add  x3, x0, x2         # x0 = 0 (en MEM/WB "se escribio" 7), x2 desde EX/MEM
        lui  x0, 0x12345
        sw   x0, 0x40(x0)       # guarda 0 en 0x40
        halt
