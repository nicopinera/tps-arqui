# Ordenamiento burbuja de 8 números con signo en la DMEM: loads, stores, dos loops anidados y
# un load-use en cada comparación (el slt usa lo que acaba de cargar el lw).
# Primero escribe el arreglo desordenado en 0x000…0x01c y después lo ordena en el lugar.
# Esperado: [0x000…0x01c] = -3 0 1 4 7 9 12 25 (el -3 es 0xfffffffd); x1 = 0, x3 = 0.
        addi x5, x0, 9
        sw   x5, 0(x0)
        addi x5, x0, 4
        sw   x5, 4(x0)
        addi x5, x0, -3
        sw   x5, 8(x0)
        addi x5, x0, 25
        sw   x5, 12(x0)
        sw   x0, 16(x0)         # 0
        addi x5, x0, 12
        sw   x5, 20(x0)
        addi x5, x0, 7
        sw   x5, 24(x0)
        addi x5, x0, 1
        sw   x5, 28(x0)
# Cada pasada lleva el mayor que queda al final; la siguiente compara uno menos.
        addi x1, x0, 7          # pasadas que faltan (n - 1)
externo:
        addi x2, x0, 0          # puntero al par que se compara
        addi x3, x1, 0          # comparaciones de esta pasada
interno:
        lw   x6, 0(x2)
        lw   x7, 4(x2)
        slt  x8, x7, x6         # load-use: x7 recién cargado. x8 = 1 si están al revés
        beq  x8, x0, en_orden   # no hay bge en el TP: slt + beq
        sw   x7, 0(x2)          # intercambio
        sw   x6, 4(x2)
en_orden:
        addi x2, x2, 4
        addi x3, x3, -1
        bne  x3, x0, interno
        addi x1, x1, -1
        bne  x1, x0, externo
        halt
