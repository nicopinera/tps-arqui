# Programa sin halt (ADR-010): el ensamblador avisa y agrega uno al final, asi que igual
# termina con HALTED. Resultado: x3 = 30.
        addi x1, x0, 10
        addi x2, x0, 20
        add  x3, x1, x2
