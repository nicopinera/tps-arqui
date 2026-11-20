# Tipo I de desplazamiento: slli, srli, srai, con desplazamientos de 0 a 31 (US-304).
# Casos:
#   2: slli 0x80000001 << 1 = 2
#   3: slli por 31 = 0x80000000
#   4: srli por 31 = 1
#   5: srli por 1 = 0x40000000 (rellena con ceros)
#   6: srai por 1 = 0xc0000000 (rellena con el signo)
#   7: srai por 31 = -1
#   8: slli por 0 no cambia el valor
#   9: srai de un positivo: 0x40000000 >> 4 = 0x04000000
        lui  x1, 0x80000
        addi x1, x1, 1          # 0x80000001
        lui  x2, 0x40000        # 0x40000000

# caso 2
        addi x31, x0, 2
        slli x5, x1, 1
        addi x29, x0, 2
        bne  x5, x29, falla
# caso 3
        addi x31, x0, 3
        slli x5, x1, 31
        lui  x29, 0x80000
        bne  x5, x29, falla
# caso 4
        addi x31, x0, 4
        srli x5, x1, 31
        addi x29, x0, 1
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        srli x5, x1, 1
        bne  x5, x2, falla
# caso 6
        addi x31, x0, 6
        srai x5, x1, 1
        lui  x29, 0xC0000
        bne  x5, x29, falla
# caso 7
        addi x31, x0, 7
        srai x5, x1, 31
        addi x29, x0, -1
        bne  x5, x29, falla
# caso 8
        addi x31, x0, 8
        slli x5, x1, 0
        bne  x5, x1, falla
# caso 9
        addi x31, x0, 9
        srai x5, x2, 4
        lui  x29, 0x04000
        bne  x5, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
