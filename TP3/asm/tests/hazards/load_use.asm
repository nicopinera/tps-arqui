# Riesgo load-use (US-502 AC1, US-503 AC1): un lw seguido de una instrucción que usa lo que
# cargó. El dato recién está al final de MEM, así que la Hazard Unit congela IF e ID un ciclo y
# mete una burbuja en EX; después el valor llega por forwarding desde MEM/WB.
# Con una instrucción en el medio ya no hace falta el stall (solo forwarding desde MEM/WB).
# En la Carta: la fila del primer `add` tiene ID dos veces y aparece una fila "burbuja".
# Esperado: [0x000] = 7, [0x004] = 14; x1 = 7, x2 = 14, x3 = 21.
        addi x1, x0, 7
        sw   x1, 0(x0)          # [0x000] = 7
        lw   x2, 0(x0)          # x2 = 7
        add  x2, x2, x2         # usa x2 ya: load-use → 1 stall; x2 = 14
        sw   x2, 4(x0)          # [0x004] = 14 (store-data por forwarding)
        lw   x3, 4(x0)          # x3 = 14
        nop                     # una en el medio: sin stall
        add  x3, x3, x1         # x3 = 21
        halt
