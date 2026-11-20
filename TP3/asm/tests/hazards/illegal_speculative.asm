# Palabra ilegal inmediatamente despues de un salto: era especulativa y no detiene la
# ejecucion (US-303 AC9).
# Casos: 2: x10 = 10 (paso la primera) · 3: x11 = 11 (paso la segunda)
        addi x1, x0, 1
        beq  x1, x1, sigue      # tomado: la ilegal esta en ID y se descarta
        .word 0x0000307f        # ilegal, especulativa
sigue:
        addi x10, x0, 10
        jal  x0, sigue2
        .word 0x0000307f        # ilegal despues de un jal (en IF): tambien se descarta
sigue2:
        addi x11, x0, 11

# caso 2
        addi x31, x0, 2
        addi x29, x0, 10
        bne  x10, x29, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 11
        bne  x11, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
