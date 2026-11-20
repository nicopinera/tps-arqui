# Dos instrucciones seguidas escriben x1: cuando el add está en EX, x1 está en EX/MEM (= 2) y
# también en MEM/WB (= 1). Tiene que ganar el más nuevo: EX/MEM. Si la Forwarding Unit mirara
# MEM/WB primero, x2 daría 2 en vez de 4.
# Mirar: Datapath, ciclo 4: fwd_a = fwd_b = 10 aunque MEM/WB también tenga rd = x1.
# Ciclos: 8 (4 instrucciones + 4)
# Esperado: x1 = 2, x2 = 4.
        addi x1, x0, 1
        addi x1, x0, 2
        add  x2, x1, x1         # 2 + 2, no 1 + 1
        halt
