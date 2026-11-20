# Load seguido de un store que guarda el dato cargado (US-302 AC4): no hay forwarding de MEM
# a MEM (ADR-007), asi que el nucleo frena un ciclo y el sw recibe el dato desde MEM/WB.
# Casos: 2: [0x108] = 123 · 3: [0x10c] = 0x0000ffff · 4: [0x110] = 123 · 5: [0x200] = 123
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

# caso 2
        addi x31, x0, 2
        lw   x28, 0x108(x0)
        addi x29, x0, 123
        bne  x28, x29, falla
# caso 3
        addi x31, x0, 3
        lw   x28, 0x10C(x0)
        lui  x29, 0x00010
        addi x29, x29, -1       # 0x0000ffff
        bne  x28, x29, falla
# caso 4
        addi x31, x0, 4
        lw   x28, 0x110(x0)
        addi x29, x0, 123
        bne  x28, x29, falla
# caso 5
        addi x31, x0, 5
        lw   x28, 0x200(x0)
        bne  x28, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
