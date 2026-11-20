# Forwarding del resultado de jal/jalr (pc + 4) a la primera instruccion que usa su rd
# (US-301 AC6). Despues de cada salto hay escrituras a x30 (marca) que no se ejecutan.
# Casos: 2: x2 = 0x04 · 3: x4 = 0x14 · 4: x30 = 0
        jal  x1, f              # 0x00: x1 = 0x04
        jal  x0, sigue          # 0x04: se ejecuta al volver de f
        addi x30, x0, 1         # 0x08: no se ejecuta
f:
        addi x2, x1, 0          # 0x0c: x2 = 0x04; x1 = pc + 4 del jal (llega desde MEM/WB)
        jalr x3, 0(x1)          # 0x10: vuelve a 0x04; x3 = 0x14
        addi x30, x0, 2         # 0x14: no se ejecuta
sigue:
        add  x4, x3, x0         # 0x18: 0x14

# caso 2
        addi x31, x0, 2
        addi x29, x0, 0x04
        bne  x2, x29, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 0x14
        bne  x4, x29, falla
# caso 4
        addi x31, x0, 4
        bne  x30, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
