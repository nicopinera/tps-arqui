# HALT inmediatamente despues de un beq tomado: era especulativo y no detiene la ejecucion
# (US-303 AC6).
        addi x1, x0, 1
        beq  x1, x1, sigue      # tomado: el halt de abajo esta en ID y se descarta
        halt                    # especulativo
sigue:
        addi x10, x0, 10
        bne  x10, x0, sigue2    # tomado
        halt                    # especulativo
        addi x31, x0, 1
sigue2:
        addi x11, x0, 11
        sw   x11, 0x40(x0)
        halt                    # este si termina el programa
