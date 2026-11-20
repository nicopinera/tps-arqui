# lui: carga los 20 bits altos y pone en 0 los 12 bajos (US-304). Los esperados se arman con
# addi y desplazamientos, sin lui.
# Casos:
#   2: lui 0x12345 = 0x12345000
#   3: lui 0xfffff = 0xfffff000
#   4: lui 0x80000 = 0x80000000
#   5: lui 0 = 0 (pisa un valor anterior)
#   6: lui 0x12346 + addi -1 = 0x12345fff (constante con la parte baja >= 0x800)
# caso 2
        addi x31, x0, 2
        lui  x5, 0x12345
        addi x29, x0, 0x123
        slli x29, x29, 8
        ori  x29, x29, 0x45
        slli x29, x29, 12       # 0x12345000
        bne  x5, x29, falla
# caso 3
        addi x31, x0, 3
        lui  x5, 0xFFFFF
        addi x29, x0, -1
        slli x29, x29, 12       # 0xfffff000
        bne  x5, x29, falla
# caso 4
        addi x31, x0, 4
        lui  x5, 0x80000
        addi x29, x0, 1
        slli x29, x29, 31       # 0x80000000
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        addi x5, x0, 77
        lui  x5, 0
        bne  x5, x0, falla
# caso 6
        addi x31, x0, 6
        lui  x5, 0x12346
        addi x5, x5, -1
        addi x29, x0, 0x123
        slli x29, x29, 8
        ori  x29, x29, 0x45
        slli x29, x29, 12       # 0x12345000
        ori  x29, x29, 0x7FF
        addi x28, x0, 0x7FF
        addi x28, x28, 1        # 0x800
        or   x29, x29, x28      # 0x12345fff
        bne  x5, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
