# HALT especulativo en cada vuelta de un lazo: el halt que sigue al bne entra a ID en todas
# las vueltas tomadas y recien se ejecuta a la salida (US-303 AC6).
        addi x1, x0, 4
        addi x2, x0, 0
lazo:
        addi x2, x2, 3
        addi x1, x1, -1
        bne  x1, x0, lazo       # 3 veces tomado: el halt de abajo se descarta
        halt                    # la cuarta vez se ejecuta: x2 = 12
