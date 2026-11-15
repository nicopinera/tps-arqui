# Instrucciones R: las 10, con operandos positivos, negativos y cero (US-210).
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        addi x1, x0, 100        # x1 = 100
        addi x2, x0, -7         # x2 = -7
        addi x3, x0, 3          # x3 = 3
        nop
        nop
        nop
        add  x10, x1, x2        # 93
        sub  x11, x1, x2        # 107
        sll  x12, x1, x3        # 800
        slt  x13, x2, x1        # 1: -7 < 100 con signo
        sltu x14, x2, x1        # 0: -7 sin signo es 0xfffffff9
        xor  x15, x1, x2
        srl  x16, x2, x3        # 0x1fffffff
        sra  x17, x2, x3        # -1
        or   x18, x1, x2
        and  x19, x1, x2
        sub  x20, x0, x1        # -100
        slt  x21, x1, x1        # 0: igual no es menor
        add  x0, x1, x2         # escribir x0 no tiene efecto
        nop
        nop
        nop
        add  x22, x10, x11      # 200: usa resultados de R
        halt
