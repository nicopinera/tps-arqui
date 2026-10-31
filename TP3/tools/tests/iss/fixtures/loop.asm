# Suma 1 + 2 + ... + 10 con un loop y guarda el resultado en 0x20 (US-108).
        addi x1, x0, 10         # contador
        addi x2, x0, 0          # suma
loop:
        add  x2, x2, x1
        addi x1, x1, -1
        bne  x1, x0, loop       # 10 vueltas
        sw   x2, 0x20(x0)       # [0x20] = 55
        halt                    # instrucciones: 2 + 10·3 + 1 = 33
