# Factorial con una multiplicación por sumas y desplazamientos (el núcleo no tiene la extensión
# M): guarda 1! … 7! en la DMEM. La multiplicación es una subrutina (jal / ret) con un loop
# adentro: por cada bit en 1 del multiplicador, suma el multiplicando desplazado.
# Esperado: [0x000…0x018] = 1 2 6 24 120 720 5040; x10 = 5040, x11 = 8.
        addi x10, x0, 1         # (n-1)!, arranca en 0! = 1
        addi x11, x0, 1         # n
        addi x12, x0, 8         # hasta 7!
        addi x13, x0, 0         # puntero a la DMEM
siguiente:
        addi x20, x10, 0        # multiplicando = (n-1)!
        addi x21, x11, 0        # multiplicador = n
        jal  x1, multiplicar    # x10 = n!
        sw   x10, 0(x13)
        addi x13, x13, 4
        addi x11, x11, 1
        bne  x11, x12, siguiente
        halt

# x10 = x20 * x21 (32 bits). Rompe x20, x21 y x22.
multiplicar:
        addi x10, x0, 0
paso:
        andi x22, x21, 1        # ¿el bit 0 del multiplicador?
        beq  x22, x0, sin_sumar
        add  x10, x10, x20
sin_sumar:
        slli x20, x20, 1        # multiplicando × 2
        srli x21, x21, 1        # siguiente bit
        bne  x21, x0, paso
        ret
