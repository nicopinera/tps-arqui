# Guía del ensamblador (US-106)

Cómo pasa un programa en assembly a las palabras de 32 bits que ejecuta el procesador. El código está en `TP3/tools/riscv_toolkit/assembler/`; las decisiones de diseño, en [ADR-013](../adr/ADR-013-ensamblador-propio.md); los bits de cada formato, en [formatos.md](../interfaces/formatos.md).

> Estado: US-106 completa. Las decisiones de diseño, con sus alternativas, están en la §9.

## 1. Qué hace y qué no

```txt
 programa.asm ──► ensamblar(texto) ──► Imagen
                                          │
                     US-107: salidas.py ◄─┘
                     ├─ .hex  → $readmemh en la simulación
                     ├─ .bin  → bytes little-endian ──► US-409/410: comando LOAD por UART ──► Debug Unit
                     └─ .lst  → listado para la GUI
```

El ensamblador **no** genera bytes ni habla con la UART: devuelve una `Imagen` (lista de palabras más la información para relacionarlas con la fuente). Convertir a `.bin` es la US-107 y mandarlo a la Debug Unit con el comando `LOAD` es trabajo del codec y la sesión de depuración (US-409, US-410, [protocolo.md](../protocolo.md)).

## 2. Las etapas

```txt
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

| Término                            | Qué es                                                                                                                                                          |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Token**                          | La unidad mínima con significado: `addi`, `x5`, `,`, `-1`, `loop:`.                                                                                             |
| **Lexer** (analizador léxico)      | Pasa de caracteres a tokens. No sabe si `addi x5` tiene sentido; solo reconoce las piezas. Se implementa con expresiones regulares .                            |
| **Parser** (analizador sintáctico) | Pasa de tokens a una estructura (`LineaAsm`) y rechaza lo que no tiene la forma correcta: `addi x5, x5` (falta un operando), `lw x5, x6` (falta `offset(rs1)`). |
| **Símbolo**                        | Una etiqueta y su dirección: `loop → 0x04`.                                                                                                                     |
| **Pasada**                         | Un recorrido completo por todas las líneas.                                                                                                                     |

## 3. La sintaxis de cada instrucción

El `Formato` de la ISA no alcanza para saber cómo se escriben los operandos: `addi` y `lw` son tipo I, pero uno es `rd, rs1, imm` y el otro `rd, imm(rs1)`. Por eso el parser tiene su propia tabla de sintaxis (decisión 2-A: la forma del texto es asunto del ensamblador, no de `isa/`).

| Sintaxis             | Instrucciones                                                           | Ejemplo            |
| -------------------- | ----------------------------------------------------------------------- | ------------------ |
| `rd, rs1, rs2`       | R: `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` | `add x3, x1, x2`   |
| `rd, rs1, imm`       | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`                          | `addi x5, x5, -1`  |
| `rd, rs1, shamt`     | `slli`, `srli`, `srai` (shamt 0–31)                                     | `slli x5, x5, 2`   |
| `rd, imm(rs1)`       | loads `lb`, `lh`, `lw`, `lbu`, `lhu` y `jalr`                           | `lw x5, 8(x2)`     |
| `rs2, imm(rs1)`      | stores `sb`, `sh`, `sw`                                                 | `sw x5, -4(x2)`    |
| `rs1, rs2, etiqueta` | `beq`, `bne`                                                            | `bne x5, x0, loop` |
| `rd, imm20`          | `lui`                                                                   | `lui x1, 0x12345`  |
| `rd, etiqueta`       | `jal`                                                                   | `jal x1, funcion`  |
| (nada)               | `halt` y las pseudo `nop`, `ret`                                        | `halt`             |
| `.word valor`        | directiva                                                               | `.word 0xDEADBEEF` |

Detalles que conviene tener presentes:

- **Branches y `jal` solo aceptan etiquetas** (decisión 4-A). En GNU, un número en esa posición es una dirección absoluta, no un offset; aceptarlo confundiría.
- **`jal` lleva siempre `rd`**: `jal x1, f`. La forma corta `jal f` no se acepta.
- **`lui` recibe los 20 bits altos**, como en GNU: `lui x1, 0x12345` deja `x1 = 0x12345000`. `CamposU.imm` espera el valor de 32 bits, así que el ensamblador hace `imm20 << 12` antes de llamar a `encode_u`.
- **Todo en minúsculas**: `ADDI` o `X5` son errores, igual que en `registros.py`.

## 4. Primera pasada: direcciones y símbolos

Recorre las `LineaAsm` con un **contador de posición** (*location counter*): la dirección de la próxima instrucción. Arranca en 0 y suma 4 por cada instrucción; una línea que solo tiene una etiqueta no suma. Cada vez que encuentra una etiqueta, la guarda en la **tabla de símbolos** (*symbol table*, `etiqueta → dirección`) con la dirección actual; si ya existía, es un error que cita las dos líneas:

```txt
línea 3: etiqueta 'a' duplicada (ya definida en la línea 1)
```

En el código no hay una variable "contador": las instrucciones se van agregando a una lista y la dirección es `4 * len(instrucciones)` (decisión §9.7).

Funciona porque **toda instrucción ocupa exactamente 4 bytes**, incluidas las pseudo (ADR-013 deja `li` afuera justamente porque se expande a 1 o 2 instrucciones).

Ejemplo:

```txt
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

  | Pseudo       | Expansión          |
  | ------------ | ------------------ |
  | `nop`        | `addi x0, x0, 0`   |
  | `mv rd, rs`  | `addi rd, rs, 0`   |
  | `j etiqueta` | `jal x0, etiqueta` |
  | `ret`        | `jalr x0, 0(x1)`   |

- **Mapa de líneas**: `mapa_lineas[direccion] = nro_linea` para cada instrucción de la fuente.
- **HALT final** (R-PR-1, ADR-010): si la última instrucción no es `halt`, se agrega una con la advertencia `el programa no termina en halt: se agregó uno al final` (decisión §9.8). Ese HALT no viene de ninguna línea: no aparece en `mapa_lineas`.
- **Tamaño** (R-PR-2, ADR-008): si con el HALT agregado hay más de `IMEM_DEPTH` (256) palabras, error en la línea de la primera instrucción que queda afuera (o la última del programa, si lo que no entra es el HALT agregado).

## 5. Segunda pasada: offsets y codificación

¿Por qué hacen falta dos pasadas? En la línea 4, `j fin`, todavía no se leyó la línea 6: no se sabe dónde está `fin`. Esto se llama **referencia hacia adelante**. Con la tabla de símbolos completa de la primera pasada, la segunda ya puede resolver todo.

Los branches y `jal` no guardan la dirección destino sino la **distancia desde su propia dirección** (offset relativo al PC):

```txt
 offset = simbolos[etiqueta] − dirección de la instrucción

 bne en 0x08 → loop en 0x04:  offset = 0x04 − 0x08 = −4   (salto hacia atrás)
 j   en 0x0C → fin  en 0x14:  offset = 0x14 − 0x0C = +8   (salto hacia adelante)
```

En el código (`_codificar`):

1. `_resolver` convierte cada operando: un número queda igual; una etiqueta pasa a `simbolos[etiqueta] - direccion`, o error `etiqueta inexistente` si no está en la tabla. Solo branches y `jal` llevan etiquetas, así que no hace falta preguntar qué instrucción es.
2. Se busca la instrucción en `INSTRUCCIONES` (opcode, funct3, funct7).
3. Un `match spec.formato` desarma los operandos **en el orden en que se escriben** y arma los `Campos*`:

   ```txt
   R       add rd, rs1, rs2      → [rd, rs1, rs2]
   I       addi rd, rs1, imm     → [rd, rs1, imm]
   I (MEM) lw rd, imm(rs1)       → [rd, imm, rs1]   ← el orden cambia: se mira SINTAXIS
   S       sw rs2, imm(rs1)      → [rs2, imm, rs1]
   B       beq rs1, rs2, etiq    → [rs1, rs2, offset]
   U       lui rd, imm20         → [rd, imm20]      → CamposU(imm = imm20 << 12)
   J       jal rd, etiq          → [rd, offset]
   ```

4. Se llama al `encode_*` del formato. Si `formatos.py` lanza `ErrorCodificacion`, se vuelve a lanzar como `ErrorEnsamblado` con la línea (`raise ... from error`, así la causa original queda encadenada para depurar).

El resultado del ejemplo:

```txt
 0x00  0x00300293   addi x5, x0, 3
 0x04  0xFFF28293   addi x5, x5, -1
 0x08  0xFE029EE3   bne  x5, x0, -4
 0x0C  0x0080006F   jal  x0, +8          ← expansión de j fin
 0x10  0x00000013   addi x0, x0, 0       ← expansión de nop
 0x14  0x0000000B   halt
```

Para los shifts, el `imm` lleva el `funct7` arriba: `imm = (funct7 << 5) | shamt` (ver `CamposI`). Antes de armarlo se verifica que el shamt esté en 0..31 (decisión §9.12).

## 6. Errores

Ante el primer error se corta el ensamblado (decisión 3-A) con un `ErrorEnsamblado` que lleva el número de línea, y no se genera ninguna `Imagen` (AC4):

```txt
línea 3: registro inválido 'x32'
```

| Error                                   | Lo detecta                                                                                           |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Carácter que no forma ningún token      | lexer                                                                                                |
| Mnemónico desconocido (incluido `li`)   | parser                                                                                               |
| Registro inválido (`x32`, `t0`)         | parser                                                                                               |
| Cantidad o tipo de operandos incorrecto | parser                                                                                               |
| `shamt` fuera de 0–31                   | 2ª pasada (`formatos.py` no lo ve: 40 entra en los 12 bits del imm)                                  |
| Etiqueta duplicada                      | 1ª pasada                                                                                            |
| Programa de más de 256 palabras         | 1ª pasada                                                                                            |
| Etiqueta inexistente                    | 2ª pasada                                                                                            |
| Inmediato fuera de rango, offset impar  | `isa/formatos.py` (`ErrorCodificacion`); la 2ª pasada lo convierte en `ErrorEnsamblado` con la línea |

`formatos.py` no conoce los números de línea; por eso el ensamblador atrapa `ErrorCodificacion` y lo vuelve a lanzar como `ErrorEnsamblado` con la línea de la instrucción.

## 7. La `Imagen`

| Campo          | Contenido                                          | Lo usa                              |
| -------------- | -------------------------------------------------- | ----------------------------------- |
| `palabras`     | Una palabra por instrucción, en orden de dirección | `salidas.py` (US-107), golden model |
| `simbolos`     | Etiqueta → dirección                               | listado, GUI                        |
| `mapa_lineas`  | Dirección → línea de la fuente                     | GUI: resaltar la línea en ejecución |
| `expansiones`  | Dirección → instrucción real de cada pseudo        | listado `.lst` (US-107, AC4)        |
| `advertencias` | HALT agregado, accesos desalineados (ADR-018)      | CLI `rvasm` (las imprime en stderr) |

Las direcciones son en bytes, como el PC.

**Advertencias de desalineado (ADR-018).** El hardware no da error con un acceso desalineado: ignora los bits bajos de la dirección, así que `lw x1, 6(x0)` lee la palabra de la dirección 4 sin avisar. El ensamblador solo puede detectarlo sin ejecutar el programa cuando la base es `x0`, porque ahí la dirección es el offset. Avisa (sin cortar el ensamblado) en `lw`/`sw` con offset no múltiplo de 4 y en `lh`/`lhu`/`sh` no múltiplo de 2:

```txt
línea 2: lw desalineado: la dirección 6 no es múltiplo de 4 y el hardware ignora los bits bajos (ADR-018)
```

Con otra base (`lw x1, 6(x2)`) no se puede saber sin conocer `x2`; ese caso lo detecta el golden model (US-108) al ejecutar.

## 8. Cómo se valida

- **Tests unitarios** por etapa: una prueba por instrucción, por error y por pseudo.
- **Contraste con GNU** (AC2): `test_vs_gnu.py` ensambla `tools/tests/assembler/fixtures/todas_las_instrucciones.asm` (las 32 instrucciones estándar, con extremos de inmediatos y saltos hacia adelante y hacia atrás) y lo compara contra `todas_las_instrucciones.hex`, generado con GNU y versionado. Los tests no necesitan GNU instalado.

Para regenerar el `.hex` (solo si cambia el `.asm`), desde `TP3/` en WSL, con el toolchain instalado por `make setup`:

```bash
make gnu-ref
```

Hace tres cosas:

1. `riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -mno-relax` ensambla a un objeto ELF. `-mno-relax` es importante: sin él, GNU deja los saltos a etiquetas como *relocaciones* para que los resuelva el linker (que podría acortarlos), y en el objeto quedan con offset 0.
2. `objcopy -O binary -j .text` extrae solo los bytes del código.
3. `od -An -v -t x4 -w4` los imprime como palabras de 4 bytes, una por línea. `od` lee en el orden de la máquina (x86, little-endian), que es el mismo de RISC-V, así que las palabras salen bien.

El `.asm` no lleva `halt` (GNU no lo conoce): el test verifica que el nuestro agregue uno al final y compara el resto.

## 9. Decisiones de diseño

Cada decisión con lo que se eligió, cómo funciona, cómo funcionaría la alternativa y qué problema evita. Las de alcance del lenguaje (pseudoinstrucciones, registros solo `xN`, sin `li` ni `.data`) están en [ADR-013](../adr/ADR-013-ensamblador-propio.md).

### 9.1 Lexer con expresiones regulares

- **Elegido:** una sola regex con una alternativa por tipo de token (grupos con nombre) y `re.finditer` recorriendo la línea. Explicación completa en [guia-regex.md](guia-regex.md).
- **Alternativa:** un lexer a mano, carácter por carácter: un bucle con un índice, `if c.isdigit(): leer_numero()`, `elif c == "x": ...`. Es lo que hacen los compiladores grandes (más rápido, mejores mensajes), pero son unas 100 líneas con muchos bordes (¿dónde termina un número? ¿qué pasa con un `-` suelto?).
- **Qué evita:** código largo y frágil para algo que una regex de 11 alternativas resuelve. La alternativa `OTRO` (`.`) al final garantiza que ningún carácter pase sin ser revisado.

### 9.2 La sintaxis de cada instrucción vive en el parser (`SINTAXIS`)

- **Elegido:** `parser.SINTAXIS` dice, para cada mnemónico, el tipo de cada operando: `"lw": (REG, MEM)`. Un test verifica que cubra las 33 de `INSTRUCCIONES`.
- **Alternativa:** un campo `sintaxis` en `InstructionSpec`. Funcionaría igual, pero `isa/` (que comparten el desensamblador y el golden model) quedaría atada al texto del assembly.
- **Qué evita:** mezclar "qué es la instrucción" (ISA) con "cómo se escribe" (ensamblador). El `Formato` no alcanza: `addi` y `lw` son ambos tipo I pero se escriben distinto.

### 9.3 Se corta en el primer error

- **Elegido:** el primer error lanza `ErrorEnsamblado` y no se genera nada (AC4).
- **Alternativa:** acumular los errores en una lista y seguir, como gcc. Obliga a decidir cómo continuar después de un error (¿qué dirección tiene una línea que no se pudo parsear? ¿una etiqueta mal definida cuenta?), y un error suele provocar otros falsos en cadena.
- **Qué evita:** esa complejidad y los errores en cascada. Con programas de prueba de decenas de líneas, corregir de a uno es aceptable.

### 9.4 Branches y `jal` solo aceptan etiquetas

- **Elegido:** `beq x1, x2, fin` sí; `beq x1, x2, 8` es error ("se esperaba una etiqueta y vino '8'").
- **Alternativa:** aceptar también un número. El problema es qué significa: en GNU es una **dirección absoluta**, no un offset; si acá fuera un offset, el mismo texto daría palabras distintas en los dos ensambladores.
- **Qué evita:** esa ambigüedad, y calcular offsets a mano, que es justo lo que el ensamblador viene a resolver.

### 9.5 Operandos como `list[int | str]`

- **Elegido:** `LineaAsm.operandos` guarda números (registros e inmediatos) y textos (etiquetas, que se resuelven en la segunda pasada), en el orden en que se escriben: `lw x5, -4(x2)` → `[5, -4, 2]`.
- **Alternativa:** una dataclass por tipo de operando (`Reg(5)`, `Imm(-4)`, `Mem(-4, 2)`, `Etiq("fin")`). Más explícito, pero repite lo que ya dice `SINTAXIS` (la posición 0 de `lw` es un registro) y obliga a desarmar objetos en la segunda pasada.
- **Qué evita:** tipos duplicados. A cambio, quien lee los operandos tiene que conocer el orden de escritura (ver la tabla de la §5).

### 9.6 `ensamblar` es una función, no una clase

- **Elegido:** `ensamblar(texto) -> Imagen`. Todo el estado (símbolos, lista de instrucciones) vive en variables locales mientras dura la llamada.
- **Alternativa:** la `class Assembler` que proponía la PRD, con `ensamblar` como método. Una clase sirve cuando hay **estado que sobrevive entre llamadas** o configuración que se fija una vez; acá no hay ninguno de los dos, así que sería una función con más ceremonia (`Assembler().ensamblar(t)`). Además, con el estado en `self` hay que acordarse de limpiarlo antes de ensamblar otro programa, o se mezclan las etiquetas de los dos.
- **Qué evita:** ese tipo de bug. Si mañana hace falta configuración (por ejemplo, otro tamaño de IMEM), se agrega un parámetro.

### 9.7 La dirección se deduce del índice

- **Elegido:** la primera pasada arma `instrucciones: list[LineaAsm]` solo con instrucciones; la de índice `i` está en la dirección `4 * i`.
- **Alternativa:** guardar pares `(direccion, LineaAsm)`. Funciona, pero son dos datos que dicen lo mismo y podrían contradecirse si algún día se edita la lista.
- **Qué evita:** inconsistencias. Funciona porque todas las instrucciones miden 4 bytes (ADR-013).

### 9.8 "Termina en HALT" = la última instrucción es `halt`

- **Elegido:** si la última instrucción no es `halt`, se agrega una. `halt` en el medio no cuenta, y `.word 0x0000000B` tampoco (se mira el mnemónico, no la palabra).
- **Alternativa:** no agregar nada si hay algún `halt` en cualquier lugar. Falla con un programa como `beq x1, x2, fin / halt / fin: addi ...`: si el salto se toma, se ejecuta la última instrucción y después se sigue de largo.
- **Qué evita:** programas que "se caen" del final (ADR-010). En el peor caso hay un HALT de más, que es inofensivo. Igual la IMEM está rellena con HALT (ADR-009); esto es una segunda red.

### 9.9 El límite de 256 sale de `IMEM_DEPTH`

- **Elegido:** se importa `IMEM_DEPTH` de `protocol/comandos.py`, de donde también se genera `du_defs.vh` para el hardware.
- **Alternativa:** un `256` propio en el ensamblador. Si algún día cambia el tamaño de la IMEM (ADR-008), habría que acordarse de cambiarlo en dos lugares.
- **Qué evita:** que el ensamblador y el hardware discrepen en el tamaño. Matiz: `IMEM_DEPTH` es un parámetro de memoria, no del protocolo; si molesta, se puede mover a `isa/` como se hizo con `HALT_OPCODE`.

### 9.10 Una etiqueta después del último `halt` se acepta

- **Elegido:** en `halt` seguido de `fin:`, `fin` apunta a la dirección siguiente al programa, y saltar ahí es válido.
- **Alternativa:** error "la etiqueta apunta fuera del programa".
- **Qué evita:** rechazar un patrón común (`j fin ... fin:`). Saltar ahí ejecuta el relleno de HALT de la IMEM (ADR-009), así que el procesador se detiene igual.

### 9.11 Pseudoinstrucciones como plantillas de texto

- **Elegido:** cada pseudo es una plantilla: `"mv": "addi x{0}, x{1}, 0"`. La primera pasada rellena la plantilla con los operandos (`mv x5, x6` → `"addi x5, x6, 0"`), guarda ese texto en `expansiones` y lo **vuelve a parsear** para obtener la `LineaAsm` real, con la etiqueta y la línea de la original.
- **Alternativa:** construir la `LineaAsm` real a mano (`LineaAsm(..., "addi", [ops[0], ops[1], 0], ...)`) y, aparte, el texto para el listado. Son dos representaciones de lo mismo que podrían no coincidir.
- **Qué evita:** que el listado `.lst` muestre una cosa y se codifique otra: el texto mostrado **es** el que se ensambla.

### 9.12 El rango del shamt se valida en la segunda pasada

- **Elegido:** `slli x1, x1, 32` da `shamt fuera de rango: 32 (0..31)`, en la segunda pasada, justo antes de armar `imm = (funct7 << 5) | shamt`.
- **Alternativa:** validarlo en el parser con un tipo de operando `SHAMT`. Funciona, pero agrega un tipo solo para tres instrucciones y separa la validación del lugar donde el shamt se combina con el `funct7`.
- **Qué evita:** un error silencioso. `formatos.py` no lo detecta: con shamt 40, `imm = 40` entra en los 12 bits de `encode_i`, pero el bit 5 cae dentro del campo `funct7` y la palabra resultante es otra instrucción (o una ilegal).

### 9.13 `lui` recibe los 20 bits altos

- **Elegido:** `lui x1, 0x12345` → `x1 = 0x12345000`, como en GNU y en la especificación. El ensamblador valida 0..0xFFFFF y hace `imm20 << 12` antes de `encode_u`.
- **Alternativa:** escribir el valor de 32 bits (`lui x1, 0x12345000`), como lo guarda `CamposU`. Sería incompatible con GNU y con los ejemplos de la bibliografía.
- **Qué evita:** que el `.asm` de contraste dé resultados distintos que GNU.

### 9.14 `.word` acepta valores con y sin signo

- **Elegido:** `.word -1` y `.word 0xFFFFFFFF` dan la misma palabra. El rango es `-2^31 .. 2^32 - 1` y se guarda `valor & 0xFFFFFFFF` (complemento a dos en 32 bits).
- **Alternativa:** solo sin signo. Obligaría a calcular a mano el complemento a dos de los negativos.
- **Qué evita:** cuentas a mano, y valores de más de 32 bits que se truncarían en silencio.

### 9.15 El lexer reconoce `x32` como registro

- **Elegido:** `x[0-9]+` es un `REGISTRO` para el lexer; el parser lo busca en `REGISTROS` y, si no está, da `registro inválido 'x32' (x0..x31)`.
- **Alternativa:** una regex que solo acepte `x0`–`x31`. `x32` caería en `OTRO` y el mensaje sería "carácter inesperado 'x'", que no explica nada.
- **Qué evita:** mensajes confusos. Regla general: el lexer clasifica, y el error lo informa la etapa que tiene contexto para explicarlo.
