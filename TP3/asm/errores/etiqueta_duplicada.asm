# Error: la misma etiqueta dos veces; el ensamblador no sabría a cuál saltar.
inicio:
        addi x1, x0, 1
inicio:
        addi x2, x0, 2
        halt
