# jalr: el destino es x5 + 0, un registro, así que se conoce recién en EX (como un branch).
# Se descartan las dos de atrás: 2 ciclos perdidos. Además x5 lo escribe la instrucción
# anterior: el jalr lo recibe por forwarding (EX/MEM) antes de sumar.
# Mirar: Datapath ciclo 3 (jalr en EX): forwarding A, jalr_target = 0xc, IF/ID e ID/EX en rojo.
# Ciclos: 10 (4 instrucciones + 4 + 2 de flush)
# Esperado: x1 = 8 (la dirección de vuelta), x2 = 0, x3 = 3, x5 = 12.
        addi x5, x0, 12         # 0x000: la dirección de `destino`
        jalr x1, 0(x5)          # 0x004
        addi x2, x0, 99         # 0x008: trampa
destino:
        addi x3, x0, 3          # 0x00c
        halt
