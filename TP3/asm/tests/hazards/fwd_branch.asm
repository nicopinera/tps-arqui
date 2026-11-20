# Forwarding hacia branch_cmp: el branch compara con el valor nuevo (US-301 AC7).
# Despues de cada salto tomado hay escrituras a x31 que no se tienen que ejecutar.
        addi x2, x0, 5
        addi x1, x0, 5          # x1 = 5 justo antes del beq
        beq  x1, x2, b1         # x1 desde EX/MEM, x2 desde MEM/WB: tomado
        addi x31, x0, 1         # no se ejecuta
b1:
        addi x1, x0, 6
        beq  x1, x2, mal        # 6 != 5: no tomado (con el valor viejo de x1 saltaria)
        addi x10, x0, 1
        addi x3, x0, 9
        bne  x3, x0, b2         # x3 desde EX/MEM: tomado
        addi x31, x0, 2         # no se ejecuta
b2:
        # Lazo con el contador decrementado justo antes del bne
        addi x4, x0, 4
        addi x5, x0, 0
lazo:
        addi x5, x5, 3
        addi x4, x4, -1
        bne  x4, x0, lazo       # x4 desde EX/MEM en cada vuelta
        addi x11, x5, 0         # 12
        jal  x0, fin
mal:
        addi x31, x0, 3         # no se ejecuta
fin:
        halt
