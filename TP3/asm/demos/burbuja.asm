# Ordenamiento burbuja de 8 enteros con signo, de menor a mayor (demo).
# Arreglo en 0x100: 7, -2, 15, 0, -9, 3, 3, 1.
# Resultado: [0x100 .. 0x11c] = -9, -2, 0, 1, 3, 3, 7, 15.
        addi x10, x0, 0x100     # base del arreglo
        addi x1, x0, 7
        sw   x1, 0(x10)
        addi x1, x0, -2
        sw   x1, 4(x10)
        addi x1, x0, 15
        sw   x1, 8(x10)
        sw   x0, 12(x10)
        addi x1, x0, -9
        sw   x1, 16(x10)
        addi x1, x0, 3
        sw   x1, 20(x10)
        sw   x1, 24(x10)
        addi x1, x0, 1
        sw   x1, 28(x10)

        addi x11, x0, 7         # comparaciones de la pasada (n - 1, despues una menos)
externo:
        addi x12, x0, 0         # comparacion actual
        addi x13, x10, 0        # puntero a a[i]
interno:
        lw   x14, 0(x13)        # a[i]
        lw   x15, 4(x13)        # a[i + 1]
        slt  x16, x15, x14      # a[i + 1] < a[i]: hay que intercambiar
        beq  x16, x0, sin_cambio
        sw   x15, 0(x13)
        sw   x14, 4(x13)
sin_cambio:
        addi x13, x13, 4
        addi x12, x12, 1
        bne  x12, x11, interno
        addi x11, x11, -1       # el mayor ya quedo al final
        bne  x11, x0, externo
        halt
