# Load-use: el add usa x2 justo después del lw que lo carga. El dato aparece recién al final de
# MEM, y el add lo necesita al principio de EX: no alcanza con forwarding.
# La Hazard Unit (lw en EX con rd = rs del add en ID) congela PC e IF/ID (StallF = StallD = 1)
# y vacía ID/EX (FlushE = 1): entra una burbuja a EX. Un ciclo después, el add va con x2 por
# forwarding desde MEM/WB.
# Mirar: Pipeline/Datapath ciclo 4 (stall: PC, IF/ID e ID/EX en ámbar); ciclo 5 la
# burbuja en EX; ciclo 6 el add en EX con A y B ← MEM/WB. Carta: el add tiene ID dos veces.
# Ciclos: 10 (5 instrucciones + 4 + 1 stall)
# Esperado: [0x000] = 7; x1 = 7, x2 = 7, x3 = 14.
        addi x1, x0, 7
        sw   x1, 0(x0)
        lw   x2, 0(x0)
        add  x3, x2, x2         # load-use: 1 stall
        halt
