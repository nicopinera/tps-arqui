# Branch tomado: el beq se resuelve en EX. Para entonces ya entraron las dos instrucciones de
# atrás (en IF e ID): se descartan (FlushD y FlushE) y el PC salta al destino (pc_sel = 10).
# Las "trampa" no se tienen que ejecutar: si x2 no es 0, el flush no anduvo.
# El beq compara x1 contra x1 recién escrito: el comparador también usa forwarding (EX/MEM).
# Mirar: Datapath ciclo 3 (beq en EX): IF/ID e ID/EX en rojo y el camino de ex_target al mux
# del PC. Ciclo 4: IF tiene la instrucción de `destino` y EX una burbuja.
# Ciclos: 10 (4 instrucciones + 4 + 2 de flush)
# Esperado: x1 = 1, x2 = 0, x3 = 3.
        addi x1, x0, 1
        beq  x1, x1, destino    # tomado: 2 ciclos perdidos
        addi x2, x0, 99         # trampa
        addi x2, x0, 98         # trampa
destino:
        addi x3, x0, 3
        halt
