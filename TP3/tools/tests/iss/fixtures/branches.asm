# Branches tomados y no tomados, y una llamada a función con jal/jalr (US-108).
        addi x1, x0, 5          # 0x00
        addi x2, x0, 5          # 0x04
        beq  x1, x2, igual      # 0x08: tomado
        addi x10, x0, 1         # 0x0c: no se ejecuta
igual:
        bne  x1, x2, fin        # 0x10: no tomado
        addi x11, x0, 2         # 0x14
        jal  x5, funcion        # 0x18: x5 = 0x1c
        addi x12, x0, 3         # 0x1c: se ejecuta al volver
fin:
        halt                    # 0x20
funcion:
        addi x13, x0, 4         # 0x24
        jalr x0, 0(x5)          # 0x28: vuelve a 0x1c
