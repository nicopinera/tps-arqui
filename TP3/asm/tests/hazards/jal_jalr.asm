# Forwarding del resultado de jal/jalr (pc + 4) a la primera instruccion que usa su rd
# (US-301 AC6). Despues de cada salto hay escrituras a x31 que no se ejecutan.
        jal  x1, f              # 0x00: x1 = 0x04
        jal  x0, sigue          # 0x04: se ejecuta al volver de f
        addi x31, x0, 1         # 0x08: no se ejecuta
f:
        addi x2, x1, 0          # 0x0c: x2 = 0x04; x1 = pc + 4 del jal (llega desde MEM/WB)
        jalr x3, 0(x1)          # 0x10: vuelve a 0x04; x3 = 0x14
        addi x31, x0, 2         # 0x14: no se ejecuta
sigue:
        add  x4, x3, x0         # 0x18: 0x14
        sw   x2, 0x40(x0)
        sw   x4, 0x44(x0)
        halt
