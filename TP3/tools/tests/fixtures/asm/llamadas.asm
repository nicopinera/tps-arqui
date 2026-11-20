# Llamadas a función con jal y ret (jalr x0, 0(x1)). jal guarda en x1 la dirección de vuelta;
# ret salta a lo que diga x1, así que el destino se conoce recién en EX. Además, el ret de la
# segunda llamada lee un x1 escrito hace dos instrucciones: necesita forwarding.
# Esperado: x10 = 12 (3 → 6 → 12), x11 = 1, x1 = 12 (0x00c: la vuelta de la segunda llamada).
        addi x10, x0, 3
        jal  x1, doble          # 0x004: vuelve a 0x008
        jal  x1, doble          # 0x008: vuelve a 0x00c
        addi x11, x0, 1         # 0x00c
        halt

# x10 = 2 * x10
doble:
        add  x10, x10, x10
        ret
