# Aritmética con valores con signo (US-108). Resultados en x10..x15.
        addi x1, x0, 100
        addi x2, x0, -7         # x2 = 0xFFFFFFF9
        add  x10, x1, x2        # 100 + (-7) = 93
        sub  x11, x2, x1        # -7 - 100 = -107 = 0xFFFFFF95
        slt  x12, x2, x1        # -7 < 100 con signo: 1
        sltu x13, x2, x1        # 0xFFFFFFF9 < 100 sin signo: 0
        srai x14, x2, 1         # -7 >> 1 = -4 (redondea hacia abajo) = 0xFFFFFFFC
        lui  x15, 0xABCDE
        ori  x15, x15, 0x123    # 0xABCDE123
        halt
