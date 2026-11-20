# jal: el destino (PC + inmediato) no depende de ningún registro, así que se calcula en ID.
# Solo hay que descartar la instrucción que entró detrás (en IF): FlushD, 1 ciclo perdido.
# Mirar: Datapath ciclo 1 (jal en ID): IF/ID en rojo, pc_sel = 01 (jal_target).
# Ciclos: 8 (3 instrucciones + 4 + 1 de flush)
# Esperado: x1 = 4 (la dirección de vuelta), x2 = 0, x3 = 3.
        jal  x1, destino        # 0x000
        addi x2, x0, 99         # 0x004: trampa
destino:
        addi x3, x0, 3          # 0x008
        halt
