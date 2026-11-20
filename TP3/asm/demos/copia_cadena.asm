# Copia una cadena terminada en 0 byte a byte con lbu/sb (demo).
# Origen en 0x100: "Hola RISC-V" (11 caracteres + el 0). Destino: 0x180.
# Resultado: [0x180 .. 0x18b] = [0x100 .. 0x10b] y x12 = 11 (largo).
        addi x10, x0, 0x100     # origen
        lui  x1, 0x616C7
        addi x1, x1, -184       # "Hola" = 0x616c6f48
        sw   x1, 0(x10)
        lui  x1, 0x53495
        addi x1, x1, 544        # " RIS" = 0x53495220
        sw   x1, 4(x10)
        lui  x1, 0x00563
        addi x1, x1, -701       # "C-V\0" = 0x00562d43
        sw   x1, 8(x10)

        addi x11, x0, 0x180     # destino
        addi x12, x0, 0         # largo
lazo:
        lbu  x13, 0(x10)
        sb   x13, 0(x11)        # copia tambien el 0 del final
        beq  x13, x0, fin
        addi x10, x10, 1
        addi x11, x11, 1
        addi x12, x12, 1
        j    lazo
fin:
        halt
