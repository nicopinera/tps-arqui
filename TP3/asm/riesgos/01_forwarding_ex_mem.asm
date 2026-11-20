# Forwarding desde EX/MEM (distancia 1): el add usa x1 un ciclo después del addi que lo escribe.
# Cuando el add está en EX, x1 = 5 todavía no llegó al banco: está en el latch EX/MEM.
# La Forwarding Unit ve rs1E = rs2E = rdM = x1 y elige fwd_a = fwd_b = 10 (EX/MEM).
# Mirar: Datapath, ciclo 3 (add en EX): los cables de forwarding A y B pintados desde alu_resultM.
# Ciclos: 7 (3 instrucciones + 4 de llenado, sin stalls ni flushes)
# Esperado: x1 = 5, x2 = 10.
        addi x1, x0, 5
        add  x2, x1, x1         # A y B ← EX/MEM
        halt
