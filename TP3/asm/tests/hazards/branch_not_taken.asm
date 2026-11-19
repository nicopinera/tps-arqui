# Branch no tomado: las instrucciones siguientes se ejecutan normalmente (US-303 AC2; la
# penalidad de 0 ciclos la cuenta tb_core_control).
        addi x1, x0, 1
        addi x2, x0, 2
        beq  x1, x2, mal        # no tomado
        addi x10, x0, 10        # se ejecuta
        bne  x1, x1, mal        # no tomado
        addi x11, x0, 11        # se ejecuta
        beq  x0, x1, mal        # no tomado
        addi x12, x0, 12        # se ejecuta
        jal  x0, fin
mal:
        addi x31, x0, 1         # no se ejecuta
fin:
        halt
