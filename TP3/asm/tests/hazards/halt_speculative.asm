# HALT especulativo en cada vuelta de un lazo (US-303 AC6): el halt que sigue al bne entra a ID
# en todas las vueltas y siempre se descarta. Se sale del lazo con el beq (en la ultima vuelta
# el bne y el halt se descartan).
# Casos: 2: x2 = 12 (4 vueltas)
        addi x1, x0, 4
        addi x2, x0, 0
lazo:
        addi x2, x2, 3
        addi x1, x1, -1
        beq  x1, x0, salida     # tomado solo en la cuarta vuelta
        bne  x1, x0, lazo       # tomado en las tres primeras: el halt de abajo se descarta
        halt                    # especulativo: nunca se ejecuta
salida:

# caso 2
        addi x31, x0, 2
        addi x29, x0, 12
        bne  x2, x29, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
