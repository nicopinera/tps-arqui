# Forwarding sobre rs2 de un store: se guarda el valor nuevo (US-301 AC5).
# Casos: 2: [0x100] = 77 · 3: [0x104] = -1 · 4: [0x108] = 0x55 · 5: [0x10c] = 76
#        6: [0x200] = 77 (base forwardeada)
        addi x6, x0, 0x100      # base
        addi x5, x0, 77
        sw   x5, 0(x6)          # x5 desde EX/MEM; x6 desde MEM/WB
        addi x7, x0, -1
        addi x8, x0, 0
        sw   x7, 4(x6)          # x7 desde MEM/WB
        addi x9, x0, 0x55
        sb   x9, 8(x6)          # store de byte con el dato forwardeado
        add  x10, x5, x7        # 76
        sh   x10, 12(x6)        # media palabra forwardeada
        addi x11, x0, 0x200
        sw   x5, 0(x11)         # la base forwardeada desde EX/MEM

# caso 2
        addi x31, x0, 2
        lw   x28, 0x100(x0)
        addi x29, x0, 77
        bne  x28, x29, falla
# caso 3
        addi x31, x0, 3
        lw   x28, 0x104(x0)
        addi x29, x0, -1
        bne  x28, x29, falla
# caso 4
        addi x31, x0, 4
        lw   x28, 0x108(x0)
        addi x29, x0, 0x55
        bne  x28, x29, falla
# caso 5
        addi x31, x0, 5
        lw   x28, 0x10C(x0)
        addi x29, x0, 76
        bne  x28, x29, falla
# caso 6
        addi x31, x0, 6
        lw   x28, 0x200(x0)
        addi x29, x0, 77
        bne  x28, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
