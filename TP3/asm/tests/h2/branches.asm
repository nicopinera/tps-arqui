# beq y bne tomados y no tomados, hacia adelante y hacia atras (US-210, AC3b).
# Despues de cada salto tomado hay instrucciones que escribirian x31 o la memoria: no se
# tienen que ejecutar (el flush las descarta).
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        addi  x1, x0, 5
        addi  x2, x0, 5
        addi  x3, x0, 7
        nop
        nop
        nop
        beq   x1, x2, b1        # tomado
        addi  x31, x0, 1        # no se ejecuta
        sw    x31, 0(x0)        # no se ejecuta
b1:
        beq   x1, x3, mal       # no tomado
        addi  x10, x0, 1        # se ejecuta
        bne   x1, x3, b2        # tomado
        addi  x31, x0, 2        # no se ejecuta
        sw    x31, 4(x0)        # no se ejecuta
b2:
        bne   x1, x2, mal       # no tomado
        addi  x11, x0, 2        # se ejecuta
        beq   x0, x0, b3        # tomado: salta hacia adelante sobre una zona larga
mal:
        addi  x31, x0, 3        # no se ejecuta
        sw    x31, 8(x0)
        addi  x30, x0, 3
b3:
        # Lazo hacia atras: el addi despues del bne se busca de mas en cada vuelta tomada y
        # solo se ejecuta una vez, a la salida
        addi  x4, x0, 3         # contador
        addi  x5, x0, 0         # acumulador
        nop
        nop
        nop
lazo:
        addi  x5, x5, 10
        addi  x4, x4, -1
        nop
        nop
        nop
        bne   x4, x0, lazo
        addi  x12, x12, 1       # 1: una sola vez
        sw    x5, 0x40(x0)      # [0x40] = 30
        # HALT especulativo: el halt de abajo entra a ID mientras el bne esta en EX y salta.
        # Tiene que descartarse y la busqueda tiene que seguir.
        addi  x6, x0, 2
        nop
        nop
        nop
lazo2:
        addi  x6, x6, -1
        nop
        nop
        nop
        bne   x6, x0, lazo2
        halt
