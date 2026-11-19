# Branch no tomado: las instrucciones siguientes se ejecutan normalmente (US-303 AC2; la
# penalidad de 0 ciclos la cuenta tb_core_control).
# Casos: 2: x10 = 10 · 3: x11 = 11 · 4: x12 = 12 · 5: x30 = 0 (no se fue a "mal")
        addi x1, x0, 1
        addi x2, x0, 2
        beq  x1, x2, mal        # no tomado
        addi x10, x0, 10        # se ejecuta
        bne  x1, x1, mal        # no tomado
        addi x11, x0, 11        # se ejecuta
        beq  x0, x1, mal        # no tomado
        addi x12, x0, 12        # se ejecuta
        jal  x0, chequeo
mal:
        addi x30, x0, 1         # no se ejecuta

chequeo:
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
        addi x29, x0, 12
        bne  x12, x29, falla
# caso 5
        addi x31, x0, 5
        bne  x30, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
