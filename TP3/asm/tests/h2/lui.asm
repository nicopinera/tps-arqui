# lui sola y combinada con addi para armar constantes de 32 bits (US-210).
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        lui   x1, 0             # 0
        lui   x2, 0xfffff       # 0xfffff000
        lui   x3, 0x80000       # 0x80000000
        lui   x4, 0x12345
        lui   x5, 0x12345
        nop
        nop
        nop
        addi  x4, x4, 0x678     # 0x12345678
        addi  x5, x5, -1        # 0x12344fff: el addi negativo resta del lui
        lui   x0, 0xabcde       # escribir x0 no tiene efecto
        halt
