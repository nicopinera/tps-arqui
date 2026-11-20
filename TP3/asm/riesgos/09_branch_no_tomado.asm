# Branch no tomado: el pipeline ya venía buscando la instrucción siguiente (predicción "no
# tomado"), así que no se pierde nada: ni flush ni burbujas.
# Mirar: Datapath ciclo 3 (bne en EX): eq = 1 pero bne salta si son distintos; pc_sel = 00.
# Ciclos: 8 (4 instrucciones + 4)
# Esperado: x1 = 1, x2 = 2.
        addi x1, x0, 1
        bne  x1, x1, lejos      # no tomado: sin flush
        addi x2, x0, 2          # se ejecuta
lejos:
        halt
