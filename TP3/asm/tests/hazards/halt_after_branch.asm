# HALT inmediatamente despues de un branch tomado: era especulativo y no detiene la ejecucion
# (US-303 AC6). El unico halt que termina el programa es el de la firma.
# Casos: 2: x10 = 10 (paso el primer halt) · 3: x11 = 11 (paso el segundo) · 4: x30 = 0
        addi x1, x0, 1
        beq  x1, x1, sigue      # tomado: el halt de abajo esta en ID y se descarta
        halt                    # especulativo
sigue:
        addi x10, x0, 10
        bne  x10, x0, sigue2    # tomado
        halt                    # especulativo
        addi x30, x0, 1
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
# caso 4
        addi x31, x0, 4
        bne  x30, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
