# Branch tomado: las 2 instrucciones que siguen en memoria nunca escriben (US-303 AC1) y un
# lazo con contador da la cantidad exacta de vueltas (AC3).
        addi x1, x0, 3
        addi x2, x0, 3
        beq  x1, x2, b1         # tomado: lo de IF e ID se descarta
        addi x31, x0, 1         # no se ejecuta (estaba en ID)
        sw   x1, 0(x0)          # no se ejecuta (estaba en IF)
b1:
        bne  x1, x0, b2         # tomado
        addi x30, x0, 1         # no se ejecuta
        addi x29, x0, 1         # no se ejecuta
b2:
        # Lazo: 5 vueltas (el contador se usa en el bne justo despues: forwarding)
        addi x3, x0, 5
        addi x4, x0, 0
lazo:
        addi x4, x4, 1          # cuenta las vueltas
        addi x3, x3, -1
        bne  x3, x0, lazo
        sw   x4, 0x40(x0)       # [0x40] = 5
        halt
