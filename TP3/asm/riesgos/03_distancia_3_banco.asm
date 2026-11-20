# Distancia 3: ya no hace falta forwarding. El addi escribe x1 en WB en el mismo ciclo en que el
# add lo lee en ID: el banco de registros escribe en el primer medio ciclo (o lo deja pasar con
# un bypass interno) y el add lee el valor nuevo. Si eso fallara, x2 daría 0.
# Mirar: Datapath, ciclo 5 (add en EX): fwd_a = fwd_b = 00, los valores vienen del banco.
# Ciclos: 9 (5 instrucciones + 4)
# Esperado: x1 = 5, x2 = 10.
        addi x1, x0, 5
        nop
        nop
        add  x2, x1, x1         # lo da el banco, sin forwarding
        halt
