# Forwarding (US-502 AC3): cada instrucción usa el resultado de la anterior (EX/MEM → EX) o de
# la de dos antes (MEM/WB → EX). Sin la Forwarding Unit, leería valores viejos del banco.
# Tres casos borde:
# - las dos fuentes a la vez (A de EX/MEM y B de MEM/WB);
# - x0: escribir x0 no se forwardea (sigue valiendo 0);
# - tres instrucciones atrás: no hay forwarding, el banco tiene que dar el valor que se está
#   escribiendo en ese mismo ciclo (escritura en el primer medio ciclo, o bypass interno).
# Esperado: x1 = 5, x2 = 10, x3 = 15, x4 = 25, x5 = 30, x6 = 15, x7 = 15, x8 = 1, x9 = 2.
        addi x1, x0, 5
        add  x2, x1, x1         # A y B ← EX/MEM: 10
        add  x3, x2, x1         # A ← EX/MEM (x2), B ← MEM/WB (x1): 15
        add  x4, x3, x2         # A ← EX/MEM, B ← MEM/WB: 25
        nop
        add  x5, x4, x1         # x4 de dos atrás: A ← MEM/WB: 30
        sub  x6, x5, x3         # 30 - 15 = 15
        add  x0, x6, x6         # escribe x0: se descarta
        add  x7, x0, x6         # A no se toma de EX/MEM (rd = x0): 0 + 15 = 15
        addi x8, x0, 1
        nop
        nop
        add  x9, x8, x8         # x8 de tres atrás, por el banco de registros: 2
        halt
