# Loads y stores de 1, 2 y 4 bytes (US-108). Base en 0x100.
        addi x1, x0, 0x100
        addi x2, x0, -2         # x2 = 0xFFFFFFFE
        sw   x2, 0(x1)          # [0x100] = FFFFFFFE
        addi x3, x0, 0x7F
        sb   x3, 4(x1)          # [0x104] = 0000007F
        sh   x2, 6(x1)          # [0x104] = FFFE007F (bytes 7F 00 FE FF)
        lb   x10, 0(x1)         # byte 0xFE con signo: 0xFFFFFFFE
        lbu  x11, 0(x1)         # byte 0xFE sin signo: 0x000000FE
        lh   x12, 6(x1)         # 0xFFFE con signo: 0xFFFFFFFE
        lhu  x13, 6(x1)         # 0xFFFE sin signo: 0x0000FFFE
        lw   x14, 4(x1)         # 0xFFFE007F
        halt
