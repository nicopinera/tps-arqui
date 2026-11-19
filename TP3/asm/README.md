# Programas en assembly

Programas RV32I para el núcleo del TP3. Se escriben con la sintaxis del ensamblador propio
(`tools/riscv_toolkit/assembler/`): registros `x0`–`x31`, comentarios con `#`, pseudos `nop`, `mv`,
`j` y `ret`, y `halt` (si falta, el ensamblador lo agrega al final).

| Carpeta          | Contenido                                                                          | Firma |
| ---------------- | ---------------------------------------------------------------------------------- | ----- |
| `tests/instr/`   | Un programa por instrucción o familia, con casos borde (US-304)                    | Sí    |
| `tests/hazards/` | Un programa por caso de riesgo de datos o de control (US-301 a US-304)             | Sí    |
| `tests/h2/`      | Programas del Hito 2, con 3 `nop` entre dependencias (US-210)                      | No    |
| `demos/`         | Programas para la defensa: arreglos, Fibonacci, cadenas, ordenamiento, subrutinas  | No    |
| `special/`       | Casos de terminación: sin HALT, lazo infinito (ABORT) e instrucción ilegal         | No    |

## Firma (ADR-014)

Cada programa de `tests/instr/` y `tests/hazards/` se verifica solo: compara cada resultado con el
valor esperado y, al terminar, escribe una **firma** en la última palabra de la DMEM:

| Dirección | Valor   | Significado                                                       |
| --------- | ------- | ----------------------------------------------------------------- |
| `0x3FC`   | `0`     | El programa no llegó al final (la DMEM arranca en 0)              |
| `0x3FC`   | `1`     | Todos los casos pasaron                                           |
| `0x3FC`   | `n ≥ 2` | Falló el caso `n` (los casos se numeran desde 2 para no confundirse con el éxito) |

Ningún programa usa `0x3FC` para otra cosa. La firma es una palabra escrita, así que siempre
aparece en la memoria usada (ADR-008).

Además de la firma, `make sim-programs` (y en US-305, `make verify`) compara el estado final
completo con el golden model: la firma dice *qué caso* falló sin tener el golden model a mano
(por ejemplo, en la placa o en la defensa).

### Registros reservados

En los programas con firma:

| Registro    | Uso                                                                              |
| ----------- | -------------------------------------------------------------------------------- |
| `x31`       | Número del caso que se está verificando                                          |
| `x30`       | Marca de camino equivocado: una instrucción que no debería ejecutarse lo escribe; se verifica que quede en 0 |
| `x28`/`x29` | Temporales del chequeo (valor leído y valor esperado)                            |

El resto (`x1`–`x27`) queda libre para lo que se prueba.

### Plantilla

```asm
# <qué prueba> (US-XXX)
# Casos:
#   2: <caso>
#   3: <caso>
        ...                     # lo que se prueba, sin chequeos en el medio si eso cambia el riesgo

# caso 2: <qué se verifica>
        addi x31, x0, 2
        addi x29, x0, 40        # esperado
        bne  x4, x29, falla
# caso 3: ...
        addi x31, x0, 3
        ...

ok:
        addi x28, x0, 1
        sw   x28, 0x3FC(x0)     # firma = 1
        halt
falla:
        sw   x31, 0x3FC(x0)     # firma = caso que falló
        halt
```

- Los valores esperados se escriben a mano en el programa (con `lui`/`addi`), **no** se calculan
  con la instrucción que se prueba, así un error en esa instrucción no se cancela en el chequeo.
- En `tests/hazards/` los chequeos van **después** de la secuencia con riesgo: si se intercalaran,
  agregarían distancia entre productora y consumidora y el riesgo dejaría de existir.
- Cada archivo empieza con un comentario que dice qué prueba y qué valores espera. La cantidad
  de ciclos no se escribe a mano: la mide `make verify` (US-305).

## Cómo correrlos

Desde `TP3/`:

```bash
make sim-programs                     # h2/, hazards/ e instr/ en el núcleo, contra el golden model
make test-py                          # incluye tests/test_asm_suite.py: toda la carpeta en el golden model
```

Un programa suelto, desde `TP3/tools/`:

```bash
uv run python -m riscv_toolkit asm ../asm/tests/instr/loads.asm -o -        # código máquina
uv run python -m riscv_toolkit sim ../asm/tests/instr/loads.asm             # estado final
```
