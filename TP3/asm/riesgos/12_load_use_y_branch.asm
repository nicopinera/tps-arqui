# Los dos tipos juntos: el beq compara un valor recién cargado. Primero load-use (el beq en ID
# espera un ciclo a que el lw llegue a MEM/WB: stall + burbuja), después el beq en EX recibe x2
# por forwarding, sale tomado y descarta las dos de atrás (flush).
# Mirar: Datapath ciclo 4 (stall: ámbar), ciclo 6 (beq en EX: A ← MEM/WB, flush: rojo).
# Ciclos: 13 (6 instrucciones + 4 + 1 stall + 2 de flush)
# Esperado: [0x000] = 5; x1 = 5, x2 = 5, x3 = 0, x4 = 4.
        addi x1, x0, 5
        sw   x1, 0(x0)
        lw   x2, 0(x0)
        beq  x2, x1, igual      # load-use y después branch tomado
        addi x3, x0, 99         # trampa
        addi x3, x0, 98         # trampa
igual:
        addi x4, x0, 4
        halt
