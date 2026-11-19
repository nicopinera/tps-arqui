# Tipo R aritmeticas: add, sub, slt, sltu, con desborde y comparaciones con y sin signo (US-304).
# Casos:
#   2: add 0x7fffffff + 1 = 0x80000000 (desborda sin excepcion)
#   3: add -1 + 1 = 0
#   4: sub 0x80000000 - 1 = 0x7fffffff
#   5: sub 0 - 1 = -1
#   6: sub x - x = 0
#   7: slt -1 < 1 = 1 (con signo)
#   8: slt 1 < -1 = 0
#   9: slt 0x80000000 < 0x7fffffff = 1 (minimo contra maximo)
#  10: slt 1 < 1 = 0
#  11: sltu 0xffffffff < 1 = 0 (sin signo)
#  12: sltu 1 < 0xffffffff = 1
#  13: sltu 0 < 1 = 1
#  14: add con rd = x0 no escribe
        lui  x4, 0x80000        # 0x80000000
        addi x1, x4, -1         # 0x7fffffff
        addi x2, x0, 1
        addi x3, x0, -1

# caso 2
        addi x31, x0, 2
        add  x5, x1, x2
        bne  x5, x4, falla
# caso 3
        addi x31, x0, 3
        add  x5, x3, x2
        bne  x5, x0, falla
# caso 4
        addi x31, x0, 4
        sub  x5, x4, x2
        bne  x5, x1, falla
# caso 5
        addi x31, x0, 5
        sub  x5, x0, x2
        bne  x5, x3, falla
# caso 6
        addi x31, x0, 6
        sub  x5, x2, x2
        bne  x5, x0, falla
# caso 7
        addi x31, x0, 7
        slt  x5, x3, x2
        bne  x5, x2, falla
# caso 8
        addi x31, x0, 8
        slt  x5, x2, x3
        bne  x5, x0, falla
# caso 9
        addi x31, x0, 9
        slt  x5, x4, x1
        bne  x5, x2, falla
# caso 10
        addi x31, x0, 10
        slt  x5, x2, x2
        bne  x5, x0, falla
# caso 11
        addi x31, x0, 11
        sltu x5, x3, x2
        bne  x5, x0, falla
# caso 12
        addi x31, x0, 12
        sltu x5, x2, x3
        bne  x5, x2, falla
# caso 13
        addi x31, x0, 13
        sltu x5, x0, x2
        bne  x5, x2, falla
# caso 14
        addi x31, x0, 14
        add  x0, x2, x2
        add  x5, x0, x0
        bne  x5, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
