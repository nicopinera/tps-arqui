# Load-use: la instruccion siguiente a un load usa el registro cargado (US-302).
# El nucleo frena un ciclo y despues el dato llega por forwarding desde MEM/WB.
# Casos: 2: x4 = 80 · 3: x6 = 7 · 4: x8 = 0 · 5: x12 = 41 · 6: x13 = 0x12345000
#        7: x14 = 0 · 8: x16 = -6 · 9: x18 = 0
        addi x10, x0, 0x100     # base
        addi x1, x0, 40
        addi x2, x0, -3
        sw   x1, 0(x10)         # [0x100] = 40
        sw   x2, 4(x10)         # [0x104] = -3
        lw   x3, 0(x10)
        add  x4, x3, x3         # 80: rs1 y rs2 del load (stall)
        lw   x5, 4(x10)
        addi x6, x5, 10         # 7: tipo I (stall)
        lw   x7, 0(x10)
        sub  x8, x1, x7         # 0: el load en rs2 (stall)
        lw   x9, 0(x10)
        addi x11, x0, 1         # independiente: sin stall
        add  x12, x9, x11       # 41: el dato llega desde MEM/WB sin frenar
        lw   x13, 4(x10)
        lui  x13, 0x12345       # pisa x13 sin leerlo: sin stall
        lw   x0, 0(x10)         # escribir x0 no tiene efecto
        add  x14, x0, x0        # 0, sin stall
        lb   x15, 4(x10)        # -3 extendido
        slli x16, x15, 1        # -6: load de byte (stall)
        lw   x17, 0(x10)
        lw   x18, 0(x17)        # la direccion es el dato cargado ([40] = 0) (stall)

# caso 2
        addi x31, x0, 2
        addi x29, x0, 80
        bne  x4, x29, falla
# caso 3
        addi x31, x0, 3
        addi x29, x0, 7
        bne  x6, x29, falla
# caso 4
        addi x31, x0, 4
        bne  x8, x0, falla
# caso 5
        addi x31, x0, 5
        addi x29, x0, 41
        bne  x12, x29, falla
# caso 6
        addi x31, x0, 6
        lui  x29, 0x12345
        bne  x13, x29, falla
# caso 7
        addi x31, x0, 7
        bne  x14, x0, falla
# caso 8
        addi x31, x0, 8
        addi x29, x0, -6
        bne  x16, x29, falla
# caso 9
        addi x31, x0, 9
        bne  x18, x0, falla

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
