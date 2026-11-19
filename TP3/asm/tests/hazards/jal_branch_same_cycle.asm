# jal en ID y branch tomado en EX en el mismo ciclo: gana el branch y el jal se descarta
# (US-303 AC8): no escribe su rd ni salta.
# Casos: 2: x1 = 0 (el primer jal no escribio) · 3: x5 = 0 (el segundo tampoco)
#        4: x30 = 0 (no se fue a "mal") · 5: x10 = 10
        addi x2, x0, 1
        beq  x2, x2, destino    # tomado (en EX cuando el jal esta en ID)
        jal  x1, mal            # se descarta: x1 sigue en 0
        addi x30, x0, 1         # no se ejecuta
destino:
        addi x10, x0, 10
        bne  x10, x0, d2        # tomado
        jal  x5, mal            # se descarta
d2:
        jal  x0, chequeo
mal:
        addi x30, x0, 2         # no se ejecuta

chequeo:
# caso 2
        addi x31, x0, 2
        bne  x1, x0, falla
# caso 3
        addi x31, x0, 3
        bne  x5, x0, falla
# caso 4
        addi x31, x0, 4
        bne  x30, x0, falla
# caso 5
        addi x31, x0, 5
        addi x29, x0, 10
        bne  x10, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
