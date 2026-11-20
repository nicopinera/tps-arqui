# Forwarding del dato de un store: el sw guarda x1, que lo escribió la instrucción anterior.
# El dato a guardar (rs2) pasa por el mux de forwarding B igual que un operando de la ALU, y
# sigue como store_data (la ALU usa el inmediato: alu_src = 1).
# Mirar: Datapath, ciclo 3 (sw en EX): forwarding B pintado; store_data = 0x2a.
# Ciclos: 7 (3 instrucciones + 4)
# Esperado: [0x000] = 42; x1 = 42.
        addi x1, x0, 42
        sw   x1, 0(x0)          # rs2 ← EX/MEM
        halt
