# Load seguido de un store que guarda el dato cargado (US-302 AC4): no hay forwarding de MEM
# a MEM (ADR-007), asi que el nucleo frena un ciclo y el sw recibe el dato desde MEM/WB.
        addi x10, x0, 0x100
        addi x1, x0, 123
        addi x2, x0, -1
        sw   x1, 0(x10)         # [0x100] = 123
        sw   x2, 4(x10)         # [0x104] = -1
        lw   x3, 0(x10)
        sw   x3, 8(x10)         # [0x108] = 123: el dato del store es el load (stall)
        lw   x4, 4(x10)
        sh   x4, 12(x10)        # [0x10c] = 0x0000ffff
        lbu  x5, 0(x10)
        sb   x5, 16(x10)        # [0x110] = 123
        addi x6, x0, 0x200
        sw   x6, 20(x10)        # [0x114] = 0x200
        lw   x7, 20(x10)
        sw   x1, 0(x7)          # la base del store es el load: [0x200] = 123 (stall)
        halt
