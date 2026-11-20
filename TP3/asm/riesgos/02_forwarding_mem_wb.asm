# Forwarding desde MEM/WB (distancia 2): entre el addi y el add hay una instrucción.
# Cuando el add está en EX, el addi ya pasó a MEM/WB: fwd_a = 01 (ResultW).
# Mirar: Datapath, ciclo 4 (add en EX): forwarding A pintado desde ResultW; B queda en 00 (x0).
# Ciclos: 8 (4 instrucciones + 4)
# Esperado: x1 = 5, x2 = 5.
        addi x1, x0, 5
        nop
        add  x2, x1, x0         # A ← MEM/WB
        halt
