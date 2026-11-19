# Subrutinas con jal/ret y una pila en memoria (demo).
# - multiplicar(x10, x11) -> x10: suma y desplazamiento (sirve tambien con x10 negativo).
# - cuadrado(x10) -> x10: llama a multiplicar, asi que guarda x1 en la pila (x2) antes.
# Resultado: [0x100] = 6 * 7 = 42, [0x104] = 9^2 = 81, [0x108] = (-5)^2 = 25.
        j    inicio

cuadrado:
        addi x2, x2, -4
        sw   x1, 0(x2)          # guarda la direccion de retorno
        addi x11, x10, 0
        jal  x1, multiplicar
        lw   x1, 0(x2)          # la recupera
        addi x2, x2, 4
        ret

multiplicar:
        addi x5, x0, 0          # producto
mul_lazo:
        beq  x11, x0, mul_fin
        andi x6, x11, 1
        beq  x6, x0, mul_sig
        add  x5, x5, x10        # si el bit bajo del multiplicador es 1, suma
mul_sig:
        slli x10, x10, 1
        srli x11, x11, 1
        j    mul_lazo
mul_fin:
        addi x10, x5, 0
        ret

inicio:
        addi x2, x0, 0x300      # puntero de pila (crece hacia abajo)
        addi x20, x0, 0x100     # donde se guardan los resultados

        addi x10, x0, 6
        addi x11, x0, 7
        jal  x1, multiplicar
        sw   x10, 0(x20)        # 42

        addi x10, x0, 9
        jal  x1, cuadrado
        sw   x10, 4(x20)        # 81

        addi x10, x0, -5
        jal  x1, cuadrado
        sw   x10, 8(x20)        # 25
        halt
