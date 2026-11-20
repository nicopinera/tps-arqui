# Saltos (US-502 AC2 y AC5): un branch tomado descarta lo que entró detrás (flush), uno no
# tomado sigue de largo sin descartar nada, y un loop con bne. Las instrucciones "trampa" no se
# tienen que ejecutar: si x2 no es 0, un flush no anduvo.
# En la vista Pipeline: en el ciclo del beq tomado, IF e ID tachadas con FLUSH; el ciclo
# siguiente, IF muestra la instrucción del destino.
# Esperado: x1 = 1, x2 = 0, x3 = 3, x4 = 0, x5 = 8.
        addi x1, x0, 1
        beq  x1, x1, tomado     # tomado: las dos siguientes se descartan
        addi x2, x0, 99         # trampa
        addi x2, x0, 98         # trampa
tomado:
        bne  x1, x1, nunca      # no tomado: sin flush
        addi x3, x0, 3
        addi x4, x0, 4          # vueltas del loop
        addi x5, x0, 0
loop:
        addi x5, x5, 2          # +2 por vuelta
        addi x4, x4, -1
        bne  x4, x0, loop       # tomado 3 veces, no tomado la cuarta
        j    fin                # jal: también descarta la de atrás
nunca:
        addi x2, x0, 97         # trampa
fin:
        halt
