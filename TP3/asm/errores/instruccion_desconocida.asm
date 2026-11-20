# Error: una instrucción que no está en el TP (mul es de la extensión M, no de RV32I).
# En la GUI: Problemas marca la línea 6, el nombre del archivo lleva ● y Cargar queda
# deshabilitado ("el programa tiene un error"). Arreglo: hacer la multiplicación con sumas.
        addi x1, x0, 6
        addi x2, x0, 7
        mul  x3, x1, x2
        halt
