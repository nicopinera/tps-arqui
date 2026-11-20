# Tipo I logicas: andi, ori, xori. El inmediato se extiende con signo: -1 es 0xffffffff y -2048
# es 0xfffff800 (US-304).
# Casos:
#   2: andi 0x12345678 & 0xff = 0x78
#   3: andi con -1 no cambia el valor
#   4: andi con -2048 (0xfffff800) = 0x12345000
#   5: ori con -1 = -1
#   6: ori 0 | 0x555 = 0x555
#   7: ori 0x12345678 | 0xf0 = 0x123456f8
#   8: xori con -1 = complemento (0xedcba987)
#   9: xori 0x12345678 ^ 0xff = 0x12345687
        lui  x2, 0x12345
        addi x2, x2, 1656       # 0x12345678
        addi x1, x0, 1
        sub  x3, x0, x1         # -1

# caso 2
        addi x31, x0, 2
        andi x5, x2, 0xFF
        addi x29, x0, 0x78
        bne  x5, x29, falla
# caso 3
        addi x31, x0, 3
        andi x5, x2, -1
        bne  x5, x2, falla
# caso 4
        addi x31, x0, 4
        andi x5, x2, -2048
        lui  x29, 0x12345
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        ori  x5, x2, -1
        bne  x5, x3, falla
# caso 6
        addi x31, x0, 6
        ori  x5, x0, 0x555
        addi x29, x0, 0x555
        bne  x5, x29, falla
# caso 7
        addi x31, x0, 7
        ori  x5, x2, 0xF0
        lui  x29, 0x12345
        addi x29, x29, 1784     # 0x123456f8
        bne  x5, x29, falla
# caso 8
        addi x31, x0, 8
        xori x5, x2, -1
        sub  x29, x3, x2        # -1 - x = ~x
        bne  x5, x29, falla
# caso 9
        addi x31, x0, 9
        xori x5, x2, 0xFF
        lui  x29, 0x12345
        addi x29, x29, 1671     # 0x12345687
        bne  x5, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
