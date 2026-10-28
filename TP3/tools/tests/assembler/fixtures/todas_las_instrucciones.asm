# Las 32 instrucciones estándar del TP, para comparar contra GNU as (US-106, AC2).
# Tiene que ensamblar igual con los dos: sin pseudoinstrucciones ni halt.
# El .hex de al lado lo genera `make gnu-ref` (TP3/Makefile); no se edita a mano.

inicio:
        # R
        add   x1, x2, x3
        sub   x31, x30, x29
        sll   x4, x5, x6
        slt   x7, x8, x9
        sltu  x10, x11, x12
        xor   x13, x14, x15
        srl   x16, x17, x18
        sra   x19, x20, x21
        or    x22, x23, x24
        and   x25, x26, x27

        # I: aritméticas y lógicas, con los extremos del inmediato
        addi  x1, x0, -2048
        slti  x2, x1, 2047
        sltiu x3, x2, -1
        xori  x4, x3, 0x555
        ori   x5, x4, -0x10
        andi  x6, x5, 0

        # I: shifts, con los extremos del shamt
        slli  x7, x6, 0
        srli  x8, x7, 31
        srai  x9, x8, 17

        # I: loads y jalr
        lb    x10, -1(x2)
        lh    x11, 2(x2)
        lw    x12, -2048(x31)
        lbu   x13, 2047(x0)
        lhu   x14, 0x10(x3)
        jalr  x1, 4(x5)

        # S
        sb    x15, -1(x2)
        sh    x16, 2047(x2)
        sw    x17, -2048(x2)

        # B, hacia atrás y hacia adelante
        beq   x1, x2, inicio
        bne   x3, x4, adelante

        # U
        lui   x18, 0
        lui   x19, 0xFFFFF

adelante:
        # J, hacia atrás y hacia adelante
        jal   x1, inicio
        jal   x0, fin
        add   x0, x0, x0
fin:
        lui   x20, 0x12345
