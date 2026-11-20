# Cadena en la DMEM (US-504): escribe "Hola, RISC-V!" byte a byte con sb, terminada en 0, y
# después la recorre con lbu hasta el 0 para medir su largo (strlen).
# En la página Estado se lee en la columna ASCII; cada sb resalta la palabra y su byte.
# La DMEM es little-endian: la H (0x48) es el byte +0, el menos significativo de la palabra.
# Esperado: [0x000] = 0x616c6f48 "Hola", [0x004] = 0x4952202c ", RI",
#           [0x008] = 0x562d4353 "SC-V", [0x00c] = 0x00000021 "!"; x10 = 13 (el largo).
        addi x5, x0, 72         # 'H'
        sb   x5, 0(x0)
        addi x5, x0, 111        # 'o'
        sb   x5, 1(x0)
        addi x5, x0, 108        # 'l'
        sb   x5, 2(x0)
        addi x5, x0, 97         # 'a'
        sb   x5, 3(x0)
        addi x5, x0, 44         # ','
        sb   x5, 4(x0)
        addi x5, x0, 32         # ' '
        sb   x5, 5(x0)
        addi x5, x0, 82         # 'R'
        sb   x5, 6(x0)
        addi x5, x0, 73         # 'I'
        sb   x5, 7(x0)
        addi x5, x0, 83         # 'S'
        sb   x5, 8(x0)
        addi x5, x0, 67         # 'C'
        sb   x5, 9(x0)
        addi x5, x0, 45         # '-'
        sb   x5, 10(x0)
        addi x5, x0, 86         # 'V'
        sb   x5, 11(x0)
        addi x5, x0, 33         # '!'
        sb   x5, 12(x0)
        sb   x0, 13(x0)         # el 0 del final
# strlen: x10 = cantidad de bytes antes del 0.
        addi x10, x0, 0
        addi x11, x0, 0         # puntero
strlen:
        lbu  x12, 0(x11)
        beq  x12, x0, fin       # usa x12 recién cargado: load-use
        addi x10, x10, 1
        addi x11, x11, 1
        j    strlen
fin:
        halt
