# Tipo R de desplazamiento: sll, srl, sra. El desplazamiento usa solo los 5 bits bajos de rs2
# (US-304).
# Casos:
#   2: sll 0x80000001 << 4 = 0x00000010
#   3: srl 0x80000001 >> 4 = 0x08000000 (rellena con ceros)
#   4: sra 0x80000001 >> 4 = 0xf8000000 (rellena con el signo)
#   5: sll por 33 = sll por 1 (solo 5 bits): 0x00000002
#   6: srl por 31 = 1
#   7: sra por 31 = -1
#   8: sra de un positivo: 4 >> 4 = 0
#   9: sll por 0 no cambia el valor
#  10: srl -1 por 33 (= 1) = 0x7fffffff
        lui  x1, 0x80000
        addi x1, x1, 1          # 0x80000001
        addi x2, x0, 4
        addi x3, x0, 31
        addi x4, x0, 33
        addi x6, x0, -1

# caso 2
        addi x31, x0, 2
        sll  x5, x1, x2
        addi x29, x0, 0x10
        bne  x5, x29, falla
# caso 3
        addi x31, x0, 3
        srl  x5, x1, x2
        lui  x29, 0x08000
        bne  x5, x29, falla
# caso 4
        addi x31, x0, 4
        sra  x5, x1, x2
        lui  x29, 0xF8000
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        sll  x5, x1, x4
        addi x29, x0, 2
        bne  x5, x29, falla
# caso 6
        addi x31, x0, 6
        srl  x5, x1, x3
        addi x29, x0, 1
        bne  x5, x29, falla
# caso 7
        addi x31, x0, 7
        sra  x5, x1, x3
        bne  x5, x6, falla
# caso 8
        addi x31, x0, 8
        sra  x5, x2, x2
        bne  x5, x0, falla
# caso 9
        addi x31, x0, 9
        sll  x5, x1, x0
        bne  x5, x1, falla
# caso 10
        addi x31, x0, 10
        srl  x5, x6, x4
        lui  x29, 0x80000
        addi x29, x29, -1       # 0x7fffffff
        bne  x5, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
