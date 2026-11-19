# Accesos desalineados (ADR-018): se ignoran los bits bajos de la direccion y el resultado es
# el del acceso alineado (US-304). El golden model deja una advertencia por cada uno.
# Memoria: [0x100] = 0x11223344.
# Casos:
#   2: lw de 0x101 lee [0x100]
#   3: lw de 0x103 lee [0x100]
#   4: lh de 0x103 lee la mitad de 0x102: 0x1122
#   5: lhu de 0x101 lee la mitad de 0x100: 0x3344
#   6: sw a 0x105 escribe [0x104]
#   7: sh a 0x107 escribe la mitad alta de [0x104]: 0xbeef3344
        addi x10, x0, 0x100
        lui  x1, 0x11223
        addi x1, x1, 836        # 0x11223344
        sw   x1, 0(x10)

# caso 2
        addi x31, x0, 2
        lw   x5, 1(x10)
        bne  x5, x1, falla
# caso 3
        addi x31, x0, 3
        lw   x5, 3(x10)
        bne  x5, x1, falla
# caso 4
        addi x31, x0, 4
        lh   x5, 3(x10)
        lui  x29, 0x00001
        addi x29, x29, 290      # 0x1122
        bne  x5, x29, falla
# caso 5
        addi x31, x0, 5
        lhu  x5, 1(x10)
        lui  x29, 0x00003
        addi x29, x29, 836      # 0x3344
        bne  x5, x29, falla
# caso 6
        addi x31, x0, 6
        sw   x1, 5(x10)
        lw   x5, 4(x10)
        bne  x5, x1, falla
# caso 7
        addi x31, x0, 7
        lui  x2, 0x0000C
        addi x2, x2, -273       # 0xbeef
        sh   x2, 7(x10)
        lw   x5, 4(x10)
        lui  x29, 0xBEEF3
        addi x29, x29, 836      # 0xbeef3344
        bne  x5, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
