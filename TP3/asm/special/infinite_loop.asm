# Loop infinito (ADR-010): no termina nunca. Sirve para probar ABORT (US-410, AC5):
# después del ABORT, x1 dice cuántas vueltas dio.
        addi x1, x0, 0
loop:
        addi x1, x1, 1
        j    loop
