# Error: el branch salta a una etiqueta que no existe (está mal escrita: "fn" y no "fin").
        addi x1, x0, 3
loop:
        addi x1, x1, -1
        bne  x1, x0, loop
        beq  x0, x0, fn
fin:
        halt
