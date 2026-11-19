# Branches: beq y bne, tomados y no tomados, hacia adelante y hacia atras (US-304).
# Un branch que tiene que saltar va seguido de "jal x0, falla": si no salta, falla.
# Casos:
#   2: beq con iguales positivos: salta
#   3: beq con distintos: no salta
#   4: beq con iguales negativos (-1): salta
#   5: beq 0x80000000 contra 0: no salta (solo difiere el bit 31)
#   6: bne con distintos (1 y -1): salta
#   7: bne con iguales: no salta
#   8: bne 0x80000000 contra 0: salta
#   9: beq x0, x0: siempre salta
#  10: lazo hacia atras con bne: exactamente 3 vueltas
        addi x1, x0, 1
        addi x2, x0, 2
        addi x3, x0, -1
        addi x4, x0, -1
        lui  x5, 0x80000

# caso 2
        addi x31, x0, 2
        addi x6, x0, 1
        beq  x1, x6, c3
        jal  x0, falla
c3:
        addi x31, x0, 3
        beq  x1, x2, falla
# caso 4
        addi x31, x0, 4
        beq  x3, x4, c5
        jal  x0, falla
c5:
        addi x31, x0, 5
        beq  x5, x0, falla
# caso 6
        addi x31, x0, 6
        bne  x1, x3, c7
        jal  x0, falla
c7:
        addi x31, x0, 7
        bne  x3, x4, falla
# caso 8
        addi x31, x0, 8
        bne  x5, x0, c9
        jal  x0, falla
c9:
        addi x31, x0, 9
        beq  x0, x0, c10
        jal  x0, falla
c10:
        addi x31, x0, 10
        addi x7, x0, 3          # contador
        addi x8, x0, 0          # vueltas
lazo:
        addi x8, x8, 1
        addi x7, x7, -1
        bne  x7, x0, lazo
        addi x29, x0, 3
        bne  x8, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
