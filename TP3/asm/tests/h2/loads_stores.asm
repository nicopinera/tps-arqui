# Loads y stores de palabra, media palabra y byte, con extension de signo (US-210).
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        lui   x1, 0x87654
        addi  x5, x0, 0x100     # base
        addi  x6, x0, -1
        nop
        nop
        nop
        addi  x1, x1, 0x321     # x1 = 0x87654321
        nop
        nop
        nop
        sw    x1, 0(x5)         # [0x100] = 0x87654321
        sw    x1, 8(x5)         # [0x108] = 0x87654321
        sh    x6, 4(x5)         # [0x104] = 0x0000ffff
        sb    x6, 7(x5)         # [0x104] = 0xff00ffff
        sb    x1, 9(x5)         # [0x108] byte 1 = 0x21 -> 0x87652121
        sh    x1, 10(x5)        # [0x108] mitad alta = 0x4321 -> 0x43212121
        sw    x6, -4(x5)        # [0x0fc] = 0xffffffff, offset negativo
        lw    x10, 0(x5)        # 0x87654321
        lh    x11, 2(x5)        # 0xffff8765
        lhu   x12, 2(x5)        # 0x00008765
        lb    x13, 3(x5)        # 0xffffff87
        lbu   x14, 3(x5)        # 0x00000087
        lb    x15, 0(x5)        # 0x00000021
        lw    x16, 4(x5)        # 0xff00ffff
        lw    x17, 8(x5)        # 0x43212121
        lw    x18, -4(x5)       # 0xffffffff
        lw    x19, 0x200(x0)    # palabra nunca escrita: 0 (no cuenta como usada)
        nop
        nop
        nop
        sw    x13, 12(x5)       # [0x10c] = 0xffffff87: guarda un valor cargado
        halt
