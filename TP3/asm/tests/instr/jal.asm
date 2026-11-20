# jal: salto incondicional relativo al PC; rd = pc + 4 (US-304).
# Casos:
#   2: jal hacia adelante: salta y escribe rd = direccion del jal + 4 (0x08)
#   3: jal hacia atras: llega al destino y escribe rd (0x28)
#   4: jal x0 (pseudo j): salta sin escribir nada
        addi x31, x0, 2         # 0x00
        jal  x1, c2             # 0x04: x1 = 0x08
        jal  x0, falla          # 0x08: no se ejecuta
c2:
        addi x29, x0, 0x08
        bne  x1, x29, falla
# caso 3
        addi x31, x0, 3
        jal  x0, c3_adelante
c3_atras:
        addi x7, x0, 7          # marca que llego
        jal  x0, c3_fin
c3_adelante:
        jal  x2, c3_atras       # 0x24: x2 = 0x28
        jal  x0, falla          # no se vuelve aca
c3_fin:
        addi x29, x0, 7
        bne  x7, x29, falla
        addi x29, x0, 0x28
        bne  x2, x29, falla
# caso 4
        addi x31, x0, 4
        j    c4
        jal  x0, falla
c4:
        add  x5, x0, x0
        bne  x5, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
