# jal en ID y branch tomado en EX en el mismo ciclo: gana el branch y el jal se descarta
# (US-303 AC8): no escribe x1 ni salta.
        addi x2, x0, 1
        beq  x2, x2, destino    # tomado (en EX cuando el jal esta en ID)
        jal  x1, mal            # se descarta: x1 sigue en 0
        addi x31, x0, 1         # no se ejecuta
destino:
        addi x10, x0, 10
        bne  x10, x0, d2        # tomado
        jal  x5, mal            # se descarta
d2:
        sw   x10, 0x40(x0)
        jal  x0, fin
mal:
        addi x30, x0, 1         # no se ejecuta
fin:
        halt
