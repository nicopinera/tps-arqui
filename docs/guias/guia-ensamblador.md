# Guía del ensamblador (US-106)

Cómo pasa un programa en assembly a las palabras de 32 bits que ejecuta el procesador. El código está en `TP3/tools/riscv_toolkit/assembler/`; las decisiones de diseño, en [ADR-013](../adr/ADR-013-ensamblador-propio.md); los bits de cada formato, en [formatos.md](../interfaces/formatos.md).

> Estado: describe el diseño acordado. Las secciones se completan a medida que se implementa cada paso de la US-106.

## 1. Qué hace y qué no

```
 programa.asm ──► Assembler.ensamblar(texto) ──► Imagen
                                                   │
                     US-107: salidas.py ◄──────────┘
                     ├─ .hex  → $readmemh en la simulación
                     ├─ .bin  → bytes little-endian ──► US-409/410: comando LOAD por UART ──► Debug Unit
                     └─ .lst  → listado para la GUI
```

El ensamblador **no** genera bytes ni habla con la UART: devuelve una `Imagen` (lista de palabras más la información para relacionarlas con la fuente). Convertir a `.bin` es la US-107 y mandarlo a la Debug Unit con el comando `LOAD` es trabajo del codec y la sesión de depuración (US-409, US-410, [protocolo.md](../protocolo.md)).

## 2. Las etapas

```
 texto
   │  lexer.py      corta cada línea en tokens; descarta espacios y comentarios
   ▼
 tokens             [ETIQUETA "loop", MNEMONICO "addi", REGISTRO "x5", COMA, REGISTRO "x5", COMA, INMEDIATO "-1"]
   │  parser.py     verifica la forma de los operandos según el mnemónico
   ▼
 LineaAsm           (etiqueta="loop", mnemonico="addi", operandos=[5, 5, -1], nro_linea=2)
   │  assembler.py  1ª pasada: direcciones + tabla de símbolos
   │                2ª pasada: offsets + encode_* de isa/formatos.py
   ▼
 Imagen
```

Cada etapa usa solo lo que le dio la anterior, así que se prueba por separado (`test_lexer.py`, `test_parser.py`, `test_assembler.py`).

| Término | Qué es |
|---|---|
| **Token** | La unidad mínima con significado: `addi`, `x5`, `,`, `-1`, `loop:`. |
| **Lexer** (analizador léxico) | Pasa de caracteres a tokens. No sabe si `addi x5` tiene sentido; solo reconoce las piezas. Se implementa con expresiones regulares (ver la guía de regex). |
| **Parser** (analizador sintáctico) | Pasa de tokens a una estructura (`LineaAsm`) y rechaza lo que no tiene la forma correcta: `addi x5, x5` (falta un operando), `lw x5, x6` (falta `offset(rs1)`). |
| **Símbolo** | Una etiqueta y su dirección: `loop → 0x04`. |
| **Pasada** | Un recorrido completo por todas las líneas. |

## 3. La sintaxis de cada instrucción

El `Formato` de la ISA no alcanza para saber cómo se escriben los operandos: `addi` y `lw` son tipo I, pero uno es `rd, rs1, imm` y el otro `rd, imm(rs1)`. Por eso el parser tiene su propia tabla de sintaxis (decisión 2-A: la forma del texto es asunto del ensamblador, no de `isa/`).

| Sintaxis | Instrucciones | Ejemplo |
|---|---|---|
| `rd, rs1, rs2` | R: `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` | `add x3, x1, x2` |
| `rd, rs1, imm` | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi` | `addi x5, x5, -1` |
| `rd, rs1, shamt` | `slli`, `srli`, `srai` (shamt 0–31) | `slli x5, x5, 2` |
| `rd, imm(rs1)` | loads `lb`, `lh`, `lw`, `lbu`, `lhu` y `jalr` | `lw x5, 8(x2)` |
| `rs2, imm(rs1)` | stores `sb`, `sh`, `sw` | `sw x5, -4(x2)` |
| `rs1, rs2, etiqueta` | `beq`, `bne` | `bne x5, x0, loop` |
| `rd, imm20` | `lui` | `lui x1, 0x12345` |
| `rd, etiqueta` | `jal` | `jal x1, funcion` |
| (nada) | `halt` y las pseudo `nop`, `ret` | `halt` |
| `.word valor` | directiva | `.word 0xDEADBEEF` |

Detalles que conviene tener presentes:

- **Branches y `jal` solo aceptan etiquetas** (decisión 4-A). En GNU, un número en esa posición es una dirección absoluta, no un offset; aceptarlo confundiría.
- **`jal` lleva siempre `rd`**: `jal x1, f`. La forma corta `jal f` no se acepta.
- **`lui` recibe los 20 bits altos**, como en GNU: `lui x1, 0x12345` deja `x1 = 0x12345000`. `CamposU.imm` espera el valor de 32 bits, así que el ensamblador hace `imm20 << 12` antes de llamar a `encode_u`.
- **Todo en minúsculas**: `ADDI` o `X5` son errores, igual que en `registros.py`.

## 4. Primera pasada: direcciones y símbolos

Recorre las `LineaAsm` con un contador de dirección que arranca en 0 y suma 4 por cada instrucción (una línea que solo tiene una etiqueta no suma). Cada vez que encuentra una etiqueta, la guarda en la tabla de símbolos con la dirección actual; si ya existía, es un error.

Funciona porque **toda instrucción ocupa exactamente 4 bytes**, incluidas las pseudo (ADR-013 deja `li` afuera justamente porque se expande a 1 o 2 instrucciones).

Ejemplo:

```
 línea  fuente                        dirección
   1            addi x5, x0, 3          0x00
   2    loop:   addi x5, x5, -1         0x04     simbolos["loop"] = 0x04
   3            bne  x5, x0, loop       0x08
   4            j    fin                0x0C
   5            nop                     0x10
   6    fin:    halt                    0x14     simbolos["fin"]  = 0x14
```

También en esta pasada:

- **Pseudoinstrucciones**: se reemplazan por la instrucción real y la expansión se anota en `Imagen.expansiones` (AC6).

  | Pseudo | Expansión |
  |---|---|
  | `nop` | `addi x0, x0, 0` |
  | `mv rd, rs` | `addi rd, rs, 0` |
  | `j etiqueta` | `jal x0, etiqueta` |
  | `ret` | `jalr x0, 0(x1)` |

- **HALT final** (R-PR-1, ADR-010): si la última instrucción no es `halt`, se agrega una con una advertencia.
- **Tamaño** (R-PR-2, ADR-008): si con el HALT agregado hay más de 256 palabras, error.

## 5. Segunda pasada: offsets y codificación

¿Por qué hacen falta dos pasadas? En la línea 4, `j fin`, todavía no se leyó la línea 6: no se sabe dónde está `fin`. Esto se llama **referencia hacia adelante**. Con la tabla de símbolos completa de la primera pasada, la segunda ya puede resolver todo.

Los branches y `jal` no guardan la dirección destino sino la **distancia desde su propia dirección** (offset relativo al PC):

```
 offset = simbolos[etiqueta] − dirección de la instrucción

 bne en 0x08 → loop en 0x04:  offset = 0x04 − 0x08 = −4   (salto hacia atrás)
 j   en 0x0C → fin  en 0x14:  offset = 0x14 − 0x0C = +8   (salto hacia adelante)
```

Con los operandos ya numéricos, se busca la instrucción en `INSTRUCCIONES` (opcode, funct3, funct7), se arman los `Campos*` y se llama al `encode_*` del formato. El resultado del ejemplo:

```
 0x00  0x00300293   addi x5, x0, 3
 0x04  0xFFF28293   addi x5, x5, -1
 0x08  0xFE029EE3   bne  x5, x0, -4
 0x0C  0x0080006F   jal  x0, +8          ← expansión de j fin
 0x10  0x00000013   addi x0, x0, 0       ← expansión de nop
 0x14  0x0000000B   halt
```

Para los shifts, el `imm` lleva el `funct7` arriba: `imm = (funct7 << 5) | shamt` (ver `CamposI`).

## 6. Errores

Ante el primer error se corta el ensamblado (decisión 3-A) con un `ErrorEnsamblado` que lleva el número de línea, y no se genera ninguna `Imagen` (AC4):

```
línea 3: registro inválido 'x32'
```

| Error | Lo detecta |
|---|---|
| Carácter que no forma ningún token | lexer |
| Mnemónico desconocido (incluido `li`) | parser |
| Registro inválido (`x32`, `t0`) | parser |
| Cantidad o tipo de operandos incorrecto | parser |
| `shamt` fuera de 0–31 | parser |
| Etiqueta duplicada | 1ª pasada |
| Programa de más de 256 palabras | 1ª pasada |
| Etiqueta inexistente | 2ª pasada |
| Inmediato fuera de rango, offset impar | `isa/formatos.py` (`ErrorCodificacion`); la 2ª pasada lo convierte en `ErrorEnsamblado` con la línea |

`formatos.py` no conoce los números de línea; por eso el ensamblador atrapa `ErrorCodificacion` y lo vuelve a lanzar como `ErrorEnsamblado` con la línea de la instrucción.

## 7. La `Imagen`

| Campo | Contenido | Lo usa |
|---|---|---|
| `palabras` | Una palabra por instrucción, en orden de dirección | `salidas.py` (US-107), golden model |
| `simbolos` | Etiqueta → dirección | listado, GUI |
| `mapa_lineas` | Dirección → línea de la fuente | GUI: resaltar la línea en ejecución |
| `expansiones` | Dirección → instrucción real de cada pseudo | listado `.lst` (US-107, AC4) |
| `advertencias` | HALT agregado, accesos desalineados (ADR-018) | CLI `rvasm` (las imprime en stderr) |

Las direcciones son en bytes, como el PC.

## 8. Cómo se valida

- **Tests unitarios** por etapa: una prueba por instrucción, por error y por pseudo.
- **Contraste con GNU** (AC2): `test_vs_gnu.py` compara contra un `.hex` de referencia generado una vez con `riscv64-unknown-elf-as -march=rv32i` (lo instala `make setup`) y versionado en `tools/tests/fixtures/`. Los tests no necesitan GNU instalado.
