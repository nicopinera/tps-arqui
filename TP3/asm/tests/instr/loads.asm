# Loads: lb, lh, lw, lbu, lhu en todos los desplazamientos, con y sin extension de signo (US-304).
# Memoria: [0x100] = 0x80ff7f01 (bytes 01 7f ff 80), [0x104] = 0x7fff8000 (mitades 8000 7fff).
# Casos:
#   2: lw [0x100] = 0x80ff7f01           9: lbu [0x103] = 0x80
#   3: lw [0x104] = 0x7fff8000          10: lh  [0x104] = 0xffff8000
#   4: lb [0x100] = 0x01                11: lh  [0x106] = 0x00007fff
#   5: lb [0x101] = 0x7f                12: lh  [0x102] = 0xffff80ff
#   6: lb [0x102] = -1                  13: lhu [0x104] = 0x00008000
#   7: lb [0x103] = -128                14: lhu [0x102] = 0x000080ff
#   8: lbu [0x102] = 0xff               15: lw de una palabra nunca escrita = 0
#  16: lw con desplazamiento negativo: -8(0x108) = [0x100]
        addi x10, x0, 0x100     # base
        lui  x1, 0x80FF8
        addi x1, x1, -255       # 0x80ff7f01
        lui  x2, 0x7FFF8        # 0x7fff8000
        sw   x1, 0(x10)
        sw   x2, 4(x10)

# caso 2
        addi x31, x0, 2
        lw   x5, 0(x10)
        bne  x5, x1, falla
# caso 3
        addi x31, x0, 3
        lw   x5, 4(x10)
        bne  x5, x2, falla
# caso 4
        addi x31, x0, 4
        lb   x5, 0(x10)
        addi x29, x0, 1
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        lb   x5, 1(x10)
        addi x29, x0, 0x7F
        bne  x5, x29, falla
# caso 6
        addi x31, x0, 6
        lb   x5, 2(x10)
        addi x29, x0, -1
        bne  x5, x29, falla
# caso 7
        addi x31, x0, 7
        lb   x5, 3(x10)
        addi x29, x0, -128
        bne  x5, x29, falla
# caso 8
        addi x31, x0, 8
        lbu  x5, 2(x10)
        addi x29, x0, 0xFF
        bne  x5, x29, falla
# caso 9
        addi x31, x0, 9
        lbu  x5, 3(x10)
        addi x29, x0, 0x80
        bne  x5, x29, falla
# caso 10
        addi x31, x0, 10
        lh   x5, 4(x10)
        lui  x29, 0xFFFF8       # 0xffff8000
        bne  x5, x29, falla
# caso 11
        addi x31, x0, 11
        lh   x5, 6(x10)
        lui  x29, 0x00008
        addi x29, x29, -1       # 0x00007fff
        bne  x5, x29, falla
# caso 12
        addi x31, x0, 12
        lh   x5, 2(x10)
        lui  x29, 0xFFFF8
        addi x29, x29, 0xFF     # 0xffff80ff
        bne  x5, x29, falla
# caso 13
        addi x31, x0, 13
        lhu  x5, 4(x10)
        lui  x29, 0x00008       # 0x00008000
        bne  x5, x29, falla
# caso 14
        addi x31, x0, 14
        lhu  x5, 2(x10)
        lui  x29, 0x00008
        addi x29, x29, 0xFF     # 0x000080ff
        bne  x5, x29, falla
# caso 15
        addi x31, x0, 15
        lw   x5, 0x200(x0)
        bne  x5, x0, falla
# caso 16
        addi x31, x0, 16
        addi x11, x10, 8
        lw   x5, -8(x11)
        bne  x5, x1, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
