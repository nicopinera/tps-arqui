# El mismo load-use que 06, con una instrucción independiente metida en el medio (lo que haría
# un compilador al reordenar). Ahora el add está a distancia 2 del lw: forwarding desde MEM/WB
# y sin stall. Mismo total de ciclos que 06, pero con una instrucción útil más.
# Mirar: Resumen: 0 stalls (en 06 hay 1).
# Ciclos: 10 (6 instrucciones + 4)
# Esperado: [0x000] = 7; x1 = 7, x2 = 7, x3 = 14, x4 = 1.
        addi x1, x0, 7
        sw   x1, 0(x0)
        lw   x2, 0(x0)
        addi x4, x0, 1          # independiente: llena el hueco del stall
        add  x3, x2, x2         # A y B ← MEM/WB, sin stall
        halt
