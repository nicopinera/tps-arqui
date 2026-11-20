# Stores: sb, sh, sw. Solo se escriben los bytes que corresponden y de rs2 se toman los bits
# bajos (US-304).
# Casos (sobre [0x100], que arranca en 0x11223344; rs2 = 0x89abcdef en sb/sh):
#   2: sw 0x11223344, se lee igual
#   3: sb en el byte 1 -> 0x1122ef44
#   4: sb en el byte 3 -> 0xef22ef44
#   5: sh en la mitad alta -> 0xcdefef44
#   6: sh en la mitad baja -> 0xcdefcdef
#   7: la palabra siguiente ([0x104]) no se toco: 0
#   8: sw con desplazamiento negativo: -4(0x10c) = [0x108] = 0x89abcdef
#   9: sb de x0 escribe 0 en el byte 0 -> 0xcdefcd00
        addi x10, x0, 0x100     # base
        lui  x1, 0x11223
        addi x1, x1, 836        # 0x11223344
        lui  x2, 0x89ABD
        addi x2, x2, -529       # 0x89abcdef

# caso 2
        addi x31, x0, 2
        sw   x1, 0(x10)
        lw   x5, 0(x10)
        bne  x5, x1, falla
# caso 3
        addi x31, x0, 3
        sb   x2, 1(x10)
        lw   x5, 0(x10)
        lui  x29, 0x1122F
        addi x29, x29, -188     # 0x1122ef44
        bne  x5, x29, falla
# caso 4
        addi x31, x0, 4
        sb   x2, 3(x10)
        lw   x5, 0(x10)
        lui  x29, 0xEF22F
        addi x29, x29, -188     # 0xef22ef44
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        sh   x2, 2(x10)
        lw   x5, 0(x10)
        lui  x29, 0xCDEFF
        addi x29, x29, -188     # 0xcdefef44
        bne  x5, x29, falla
# caso 6
        addi x31, x0, 6
        sh   x2, 0(x10)
        lw   x5, 0(x10)
        lui  x29, 0xCDEFD
        addi x29, x29, -529     # 0xcdefcdef
        bne  x5, x29, falla
# caso 7
        addi x31, x0, 7
        lw   x5, 4(x10)
        bne  x5, x0, falla
# caso 8
        addi x31, x0, 8
        addi x11, x10, 0xC
        sw   x2, -4(x11)
        lw   x5, 8(x10)
        bne  x5, x2, falla
# caso 9
        addi x31, x0, 9
        sb   x0, 0(x10)
        lw   x5, 0(x10)
        lui  x29, 0xCDEFD
        addi x29, x29, -768     # 0xcdefcd00
        bne  x5, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
