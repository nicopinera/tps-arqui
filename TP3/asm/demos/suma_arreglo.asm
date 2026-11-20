# Suma de un arreglo de 8 enteros con signo (demo).
# Arreglo en 0x100: 5, -3, 12, 7, -8, 20, 1, 6. Resultado: [0x140] = x12 = 40.
        addi x10, x0, 0x100     # base del arreglo
        addi x1, x0, 5
        sw   x1, 0(x10)
        addi x1, x0, -3
        sw   x1, 4(x10)
        addi x1, x0, 12
        sw   x1, 8(x10)
        addi x1, x0, 7
        sw   x1, 12(x10)
        addi x1, x0, -8
        sw   x1, 16(x10)
        addi x1, x0, 20
        sw   x1, 20(x10)
        addi x1, x0, 1
        sw   x1, 24(x10)
        addi x1, x0, 6
        sw   x1, 28(x10)

        addi x11, x0, 8         # elementos que faltan
        addi x12, x0, 0         # suma
        addi x13, x10, 0        # puntero
lazo:
        lw   x14, 0(x13)
        add  x12, x12, x14
        addi x13, x13, 4
        addi x11, x11, -1
        bne  x11, x0, lazo
        sw   x12, 0x40(x10)     # [0x140] = 40
        halt
