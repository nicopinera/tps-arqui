# jal y jalr: hacia adelante y atras, direccion de retorno y bit 0 del destino (US-210, AC3b).
# Despues de cada salto hay instrucciones que escribirian x31 o la memoria: no se ejecutan.
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        jal   x1, adelante      # x1 = 0x04
        addi  x31, x0, 1        # no se ejecuta
        sw    x31, 0(x0)        # no se ejecuta
volver:
        addi  x11, x0, 2
        jal   x0, fin           # jal sin enlace (j)
        addi  x31, x0, 2        # no se ejecuta
adelante:
        addi  x10, x0, 1
        jal   x2, funcion       # llamada: x2 = direccion siguiente
        addi  x12, x0, 3        # se ejecuta al volver
        nop
        nop
        nop
        # jalr con destino impar: (x1 + 9) & ~1 = 0x0c = volver
        jalr  x3, 9(x1)         # x3 = direccion siguiente
        addi  x31, x0, 4        # no se ejecuta
        sw    x31, 4(x0)        # no se ejecuta
funcion:
        addi  x13, x0, 4
        nop
        nop
        nop
        jalr  x0, 0(x2)         # vuelve (ret)
        addi  x31, x0, 5        # no se ejecuta
fin:
        sw    x1, 0x40(x0)      # guarda las direcciones de retorno
        sw    x2, 0x44(x0)
        sw    x3, 0x48(x0)
        halt
