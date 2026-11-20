# Una palabra ilegal termina el programa con estado ILLEGAL (US-210, AC3c, ADR-018).
# Lo que esta antes se ejecuta; lo que esta despues no.
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        addi  x1, x0, 1
        addi  x2, x0, 2
        nop
        nop
        nop
        sw    x2, 0(x0)
        .word 0x0000307f        # opcode 1111111: no es ninguna instruccion
        addi  x31, x0, 1        # no se ejecuta
        sw    x31, 4(x0)        # no se ejecuta
        halt
