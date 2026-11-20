# Desplazamientos inmediatos y por registro (US-210).
# Hito 2, sin forwarding: 3 nop entre una instruccion y la primera que usa su resultado.
        lui   x1, 0x80000       # x1 = 0x80000000
        addi  x2, x0, 33        # shamt de registro > 31: se usan solo los 5 bits bajos (= 1)
        addi  x3, x0, 0x7f
        nop
        nop
        nop
        slli  x10, x3, 4        # 0x7f0
        srli  x11, x1, 4        # 0x08000000
        srai  x12, x1, 4        # 0xf8000000
        slli  x13, x3, 31       # 0x80000000
        srai  x14, x1, 31       # 0xffffffff
        srli  x15, x1, 31       # 1
        sll   x16, x3, x2       # 0xfe (desplaza 1)
        srl   x17, x1, x2       # 0x40000000
        sra   x18, x1, x2       # 0xc0000000
        slli  x19, x3, 0        # sin desplazar
        halt
