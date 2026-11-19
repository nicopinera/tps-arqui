# Instruccion ilegal (ADR-018): el nucleo se detiene con estado ILLEGAL y el PC queda en la
# palabra ilegal (0x0c). Lo anterior se completa: x1 = 5 y [0x40] = 5.
        addi x1, x0, 5
        sw   x1, 0x40(x0)
        nop
        .word 0x00000000        # ilegal (opcode 0000000), como una IMEM sin inicializar
        addi x2, x0, 1          # no se ejecuta
        halt
