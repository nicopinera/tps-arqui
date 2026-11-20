# Tipo I aritmeticas: addi, slti, sltiu. El inmediato de 12 bits se extiende con signo, tambien
# en sltiu (US-304). Los esperados se arman con lui y operaciones R, sin addi negativo: un error
# en la extension de signo no se cancela en el chequeo.
# Casos:
#   2: addi con inmediato negativo: 0x12345000 - 1 = 0x12344fff
#   3: addi -2048 (minimo) = 0xfffff800
#   4: addi -1 + 1 = 0
#   5: addi con rd = x0 no escribe
#   6: slti -1 < 0 = 1
#   7: slti 1 < -1 = 0
#   8: slti 0x12345000 < 2047 = 0
#   9: sltiu 1 < -1 (0xffffffff) = 1
#  10: sltiu -1 < -1 = 0
#  11: sltiu 0 < 1 = 1 (seqz)
#  12: sltiu 1 < 1 = 0
        addi x1, x0, 1
        lui  x2, 0x12345        # 0x12345000
        sub  x3, x0, x1         # -1

# caso 2
        addi x31, x0, 2
        addi x5, x2, -1
        sub  x29, x2, x1        # 0x12344fff
        bne  x5, x29, falla
# caso 3
        addi x31, x0, 3
        addi x5, x0, -2048
        lui  x29, 0xFFFFF       # 0xfffff000
        addi x28, x0, 0x400
        add  x29, x29, x28
        add  x29, x29, x28      # 0xfffff800
        bne  x5, x29, falla
# caso 4
        addi x31, x0, 4
        addi x5, x3, 1
        bne  x5, x0, falla
# caso 5
        addi x31, x0, 5
        addi x0, x1, 5
        add  x5, x0, x1
        bne  x5, x1, falla
# caso 6
        addi x31, x0, 6
        slti x5, x3, 0
        bne  x5, x1, falla
# caso 7
        addi x31, x0, 7
        slti x5, x1, -1
        bne  x5, x0, falla
# caso 8
        addi x31, x0, 8
        slti x5, x2, 2047
        bne  x5, x0, falla
# caso 9
        addi x31, x0, 9
        sltiu x5, x1, -1
        bne  x5, x1, falla
# caso 10
        addi x31, x0, 10
        sltiu x5, x3, -1
        bne  x5, x0, falla
# caso 11
        addi x31, x0, 11
        sltiu x5, x0, 1
        bne  x5, x1, falla
# caso 12
        addi x31, x0, 12
        sltiu x5, x1, 1
        bne  x5, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
