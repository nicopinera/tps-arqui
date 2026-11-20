# jalr: salto a rs1 + imm con el bit 0 en 0; rd = pc + 4 (US-304, ADR-018).
# Casos:
#   2: jalr x1, 0(x2): salta a x2 y escribe x1 = direccion del jalr + 4
#   3: desplazamiento positivo: 4(destino - 4)
#   4: desplazamiento negativo: -8(destino + 8)
#   5: destino con el bit 0 en 1: se limpia y salta al destino par
#   6: rd = rs1: el destino se calcula con el valor viejo de rs1
#   7: subrutina con jal x1 y vuelta con ret (jalr x0, 0(x1))
# caso 2
        addi x31, x0, 2         # 0x00
        addi x2, x0, 0x10       # 0x04
        jalr x1, 0(x2)          # 0x08: x1 = 0x0c
        jal  x0, falla          # 0x0c: no se ejecuta
        addi x29, x0, 0x0C      # 0x10
        bne  x1, x29, falla
# caso 3
        addi x31, x0, 3         # 0x18
        addi x2, x0, 0x24       # 0x1c: destino 0x28 - 4
        jalr x0, 4(x2)          # 0x20
        jal  x0, falla          # 0x24: no se ejecuta
# caso 4
        addi x31, x0, 4         # 0x28
        addi x2, x0, 0x40       # 0x2c: destino 0x38 + 8
        jalr x0, -8(x2)         # 0x30
        jal  x0, falla          # 0x34: no se ejecuta
# caso 5
        addi x31, x0, 5         # 0x38
        addi x2, x0, 0x49       # 0x3c: destino 0x48 + 1
        jalr x0, 0(x2)          # 0x40
        jal  x0, falla          # 0x44: no se ejecuta
# caso 6
        addi x31, x0, 6         # 0x48
        addi x3, x0, 0x58       # 0x4c
        jalr x3, 0(x3)          # 0x50: salta a 0x58 y x3 = 0x54
        jal  x0, falla          # 0x54: no se ejecuta
        addi x29, x0, 0x54      # 0x58
        bne  x3, x29, falla
# caso 7
        addi x31, x0, 7
        addi x8, x0, 0
        jal  x1, subrutina
        addi x29, x0, 5
        bne  x8, x29, falla
        j    ok

subrutina:
        addi x8, x0, 5
        ret

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que fallo
        halt
