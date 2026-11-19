# Palabra ilegal inmediatamente despues de un beq tomado: era especulativa y no detiene la
# ejecucion (US-303 AC9).
        addi x1, x0, 1
        beq  x1, x1, sigue      # tomado: la ilegal esta en ID y se descarta
        .word 0x0000307f        # ilegal, especulativa
sigue:
        addi x10, x0, 10
        jal  x0, sigue2
        .word 0x0000307f        # ilegal despues de un jal (en IF): tambien se descarta
sigue2:
        sw   x10, 0x40(x0)
        halt
