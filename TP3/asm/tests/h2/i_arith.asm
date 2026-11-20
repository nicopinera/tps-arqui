# Instrucciones I aritmeticas con inmediatos positivos, negativos y extremos (US-210).
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        addi  x1, x0, 2047      # inmediato maximo
        addi  x2, x0, -2048     # inmediato minimo
        addi  x3, x0, -1
        nop
        nop
        nop
        addi  x10, x1, 1        # 2048
        addi  x11, x2, -1       # -2049
        slti  x12, x2, -2047    # 1
        slti  x13, x1, 2047     # 0
        sltiu x14, x3, -1       # 0: 0xffffffff no es menor que 0xffffffff
        sltiu x15, x1, -1       # 1: -1 sin signo es el maximo
        xori  x16, x1, -1       # not x1
        ori   x17, x2, 15
        andi  x18, x3, 0x7f0
        addi  x19, x0, 0        # 0
        halt
        # Despues del halt: nunca llegan a EX (AC3)
        addi  x31, x0, 1
        sw    x31, 0(x0)
