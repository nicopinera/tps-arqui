# Forwarding sobre rs2 de un store: se guarda el valor nuevo (US-301 AC5).
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
        halt
