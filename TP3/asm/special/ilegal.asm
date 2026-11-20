# Instrucción ilegal (US-501 AC6): la DU para con motivo ILLEGAL y la GUI resalta la fila de la
# ilegal en el listado; en la vista Pipeline la tarjeta sale con el color de error.
# Lo que viene después no se ejecuta.
# Esperado: motivo ILLEGAL; x1 = 5, x2 = 0.
        addi x1, x0, 5
        .word 0xffffffff        # no es ninguna instrucción del TP
        addi x2, x0, 9          # no llega a ejecutarse
        halt
