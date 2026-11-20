# Tipo R logicas: and, or, xor (US-304).
# Casos:
#   2: and 0x0f0f0f0f & 0x00ff00ff = 0x000f000f
#   3: or  0x0f0f0f0f | 0x00ff00ff = 0x0fff0fff
#   4: xor 0x0f0f0f0f ^ 0x00ff00ff = 0x0ff00ff0
#   5: xor con -1 = complemento (0xf0f0f0f0)
#   6: and con 0 = 0
#   7: or con -1 = -1
#   8: xor x ^ x = 0
        lui  x1, 0x0F0F1
        addi x1, x1, -241       # 0x0f0f0f0f
        lui  x2, 0x00FF0
        addi x2, x2, 255        # 0x00ff00ff
        addi x3, x0, -1

# caso 2
        addi x31, x0, 2
        and  x5, x1, x2
        lui  x29, 0x000F0
        addi x29, x29, 15       # 0x000f000f
        bne  x5, x29, falla
# caso 3
        addi x31, x0, 3
        or   x5, x1, x2
        lui  x29, 0x0FFF1
        addi x29, x29, -1       # 0x0fff0fff
        bne  x5, x29, falla
# caso 4
        addi x31, x0, 4
        xor  x5, x1, x2
        lui  x29, 0x0FF01
        addi x29, x29, -16      # 0x0ff00ff0
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        xor  x5, x1, x3
        lui  x29, 0xF0F0F
        addi x29, x29, 240      # 0xf0f0f0f0
        bne  x5, x29, falla
# caso 6
        addi x31, x0, 6
        and  x5, x1, x0
        bne  x5, x0, falla
# caso 7
        addi x31, x0, 7
        or   x5, x1, x3
        bne  x5, x3, falla
# caso 8
        addi x31, x0, 8
        xor  x5, x2, x2
        bne  x5, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
