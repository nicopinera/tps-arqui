# Branch que compara el resultado de un load inmediatamente anterior: stall de un ciclo y
# despues la comparacion con el valor cargado (US-303 AC5).
# Casos: 2: x30 = 0 (ningun camino equivocado) · 3: x11 = 1 · 4: x12 = 1
        addi x10, x0, 0x100
        addi x1, x0, 7
        sw   x1, 0(x10)         # [0x100] = 7
        addi x2, x0, 7
        lw   x3, 0(x10)
        beq  x3, x2, b1         # x3 = 7 recien cargado: tomado
        addi x30, x0, 1         # no se ejecuta
b1:
        lw   x4, 0(x10)
        bne  x4, x2, mal        # 7 == 7: no tomado
        addi x11, x0, 1         # se ejecuta
        lw   x5, 0(x10)
        bne  x5, x0, b2         # rs1 del load: tomado
        addi x30, x0, 2         # no se ejecuta
b2:
        lw   x6, 0(x10)
        beq  x0, x6, mal        # el load en rs2: no tomado
        addi x12, x0, 1
        jal  x0, chequeo
mal:
        addi x30, x0, 3         # no se ejecuta

chequeo:
# caso 2
        addi x31, x0, 2
        bne  x30, x0, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 1
        bne  x11, x29, falla
# caso 4
        addi x31, x0, 4
        bne  x12, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
