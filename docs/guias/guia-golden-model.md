# Guía del golden model (US-108)

Cómo funciona el simulador de referencia: qué estado guarda, cómo ejecuta cada instrucción y cómo se usa su resultado para verificar el hardware. El código está en `TP3/tools/riscv_toolkit/iss/`; la decisión de tenerlo, en [ADR-014](../adr/ADR-014-golden-model.md); las reglas de memoria e ilegales, en ADR-008, ADR-009 y ADR-018.

> Estado: US-108 completa. La comparación con el hardware está en la §10; las decisiones de diseño, con sus alternativas, en la §11.

## 1. Qué es y para qué sirve

Cuando el procesador (en simulación o en la placa) termina de correr un programa, muestra sus registros y su memoria. Para saber si ese resultado es **correcto** hace falta un **resultado esperado**. Calcularlo a mano no escala a decenas de programas, así que se calcula con un programa: el **golden model** ("modelo de oro", la implementación de referencia).

Es un **ISS** (_Instruction Set Simulator_): ejecuta **una instrucción entera por paso**, siguiendo la especificación de la ISA (PRD §2.2). No modela el pipeline: no tiene etapas, forwarding, stalls ni flushes. Por eso sirve de referencia: si el pipeline está bien hecho, tiene que llegar **al mismo estado final** que el ISS.

```txt
 programa.asm ──► ensamblar ──► palabras ──► GoldenModel.run() ──► EstadoArquitectonico
                                   │                                     │
                                   │                     ┌───────────────┼──────────────────┐
                                   ▼                     ▼               ▼                  ▼
                            hardware (RTL/placa)   rvsim --dump    rvsim --expect     FakeTransport (US-409)
                                   │                (pantalla)     .expected            modo verificar (US-505)
                                   ▼                                     │
                             estado final ─────────── comparar ◄─────────┘  tb_core_programs.v (US-210)
                                                                            verify_rtl.py (US-305)
```

Lo que se compara es el **estado arquitectónico**: lo que "ve" el programa (PC, `x0`–`x31` y memoria). Los latches del pipeline son estado \_micro_arquitectónico y no se comparan.

## 2. Los archivos

| Archivo                | Qué tiene                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------- |
| `iss/golden_model.py`  | `GoldenModel`, `Motivo`, `EstadoArquitectonico` y las tablas de cada grupo de instrucciones |
| `iss/expected.py`      | `a_expected` y `leer_expected`: el formato `.expected` (§8)                                 |
| `cli/rvsim.py`         | el subcomando `sim` (§9)                                                                    |
| `isa/instrucciones.py` | `identificar(palabra)`, compartida con el desensamblador                                    |
| `isa/formatos.py`      | los `decode_*` y `sign_extend`                                                              |

`GoldenModel` **no importa nada del ensamblador** (AC4): recibe palabras de 32 bits, no texto. Así lo puede usar `FakeTransport`, que recibe las palabras del comando `LOAD`. Solo la CLI ensambla.

## 3. El estado

```python
modelo = GoldenModel(imem_words, dmem_words=256, imem_words_max=256)
```

| Atributo                  | Tipo             | Qué guarda                                                           | Valor inicial                |
| ------------------------- | ---------------- | -------------------------------------------------------------------- | ---------------------------- |
| `pc`                      | `int`            | dirección (en bytes) de la próxima instrucción                       | 0                            |
| `regs`                    | `list[int]`      | los 32 registros, **sin signo**                                      | todos 0                      |
| `imem`                    | `list[int]`      | la memoria de instrucciones, una palabra por elemento                | el programa + HALT hasta 256 |
| `dmem`                    | `bytearray`      | la memoria de datos, **un byte por elemento** (1024)                 | todo 0                       |
| `mem_escrita`             | `set[int]`       | direcciones (alineadas a 4) de las palabras que escribió algún store | vacío                        |
| `instrucciones_retiradas` | `int`            | instrucciones ejecutadas completas                                   | 0                            |
| `advertencias`            | `list[str]`      | avisos de accesos desalineados                                       | vacía                        |
| `motivo`                  | `Motivo \| None` | por qué terminó; `None` mientras corre                               | `None`                       |

Todo arranca en cero, igual que el hardware después de `LOAD` (ADR-009).

- **IMEM como lista de palabras.** El fetch siempre lee palabras enteras.
- **DMEM como `bytearray`.** Los loads y stores leen o escriben 1, 2 o 4 bytes.

**El constructor valida dos cosas** antes de armar nada:

- **Que el programa entre.** Más de `imem_words_max` palabras da `ValueError`.
- **Que cada palabra entre en 32 bits.** Una palabra fuera de `0 … 0xFFFFFFFF` da `ValueError`. Es la frontera de confianza: después, ninguna función interna vuelve a chequearlo.

**Por qué el relleno es HALT y no NOP.** Si un programa "se cae" por el final (por ejemplo, un salto mal calculado), la próxima palabra es un `halt` y el procesador se detiene limpio. Con `nop` seguiría hasta `0x3FC`, la dirección daría la vuelta a `0x000` y el programa se ejecutaría otra vez, para siempre.

## 4. Números de 32 bits en Python

Este es el punto más importante para entender el código.

**Los enteros de Python no tienen tamaño.** En Verilog un registro tiene 32 bits y `0xFFFFFFFF + 1` da `0` solo. En Python, `0xFFFFFFFF + 1` da `4294967296` y `0 - 1` da `-1`. El modelo tiene que **simular** los 32 bits:

| Herramienta            | Qué hace                                                                   | Ejemplo                                                               |
| ---------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `x & _MASCARA_32`      | se queda con los 32 bits bajos; convierte un negativo a su complemento a 2 | `-1 & 0xFFFFFFFF` → `0xFFFFFFFF`                                      |
| `sign_extend(x, bits)` | lee los `bits` bajos de `x` como número con signo                          | `sign_extend(0xFFFFFFFF, 32)` → `-1`; `sign_extend(0x80, 8)` → `-128` |

**Convención:** los registros siempre guardan el valor **sin signo** (`0 … 2³² − 1`), que es lo que viaja en el snapshot. Cuando una instrucción necesita el signo (`slt`, `sra`, `lb`, `lh`), convierte con `sign_extend` y vuelve con la máscara.

**La misma palabra, dos lecturas.** `0xFFFFFFFF` es `4294967295` sin signo y `-1` con signo. Los bits no cambian; cambia **cómo los interpreta la instrucción**. Por eso existen `slt` y `sltu`, `lb` y `lbu`, `sra` y `srl`.

## 5. El ciclo de una instrucción: `step()`

```txt
 1. fetch        palabra = imem[(pc // 4) % len(imem)]
 2. identificar  spec = identificar(palabra)
 3. terminar?    spec None → ILLEGAL  ·  halt → HALTED      (sin tocar nada)
 4. ejecutar     según el grupo: ALU, load, store, branch, jal, jalr, lui
 5. avanzar      pc = siguiente;  instrucciones_retiradas += 1
```

**1. Fetch** (buscar la instrucción)

- `pc // 4`: el PC está en **bytes** y la lista se indexa en **palabras**. Con PC = 8 se lee `imem[2]`.
- `% len(imem)`: si el PC se pasa del final, da la vuelta. Con PC = `0x404` se lee la palabra 1. Es lo mismo que hace el hardware, que ignora los bits altos de la dirección (ADR-008).

**2. Identificar** (`isa/instrucciones.py`)

Cada instrucción de la tabla tiene una ficha fija, `InstructionSpec`, con mnemónico, formato, opcode, funct3 y funct7. El diccionario `_INDICE` va de `(opcode, funct3, funct7)` a la ficha. `identificar` saca esos tres campos de la palabra y prueba **de la clave más específica a la menos**:

| Clave probada              | Encuentra                                | Por qué                      |
| -------------------------- | ---------------------------------------- | ---------------------------- |
| `(opcode, funct3, funct7)` | R (`add`, `sub`…) y shifts con inmediato | solo esas usan funct7        |
| `(opcode, funct3, None)`   | el resto de las I, las S y las B         | tienen funct3 pero no funct7 |
| `(opcode, None, None)`     | `lui`, `jal`, `halt`                     | solo tienen opcode           |

Si ninguna clave existe, devuelve `None`: la palabra es **ilegal**. Ejemplos:

- `0x00000000` tiene opcode 0, que no es de ninguna instrucción.
- `mul` y `blt` no están en la tabla de este procesador.

El desensamblador usa la misma función, así que los dos coinciden siempre en qué es legal.

**3. Terminar**:

- **Ilegal:** se guarda `motivo = ILLEGAL` y se devuelve **sin tocar nada**: ni registros, ni memoria, ni PC, ni el contador. Así el PC queda apuntando a la ilegal, como pide el AC2, y es lo que muestra el hardware (ADR-018).
- **`halt`:** se guarda `motivo = HALTED` y el PC también queda en el `halt`.
- **Es un valor, no una excepción.** Una ilegal no es un error del simulador: es un resultado posible de un programa. Las excepciones quedan para errores de uso, como un programa que no entra en la IMEM.

**4 y 5. Ejecutar y avanzar.** El próximo PC arranca en `siguiente = pc + 4`, el camino normal. Solo los saltos lo cambian. Al final se hace una sola vez `pc = siguiente & _MASCARA_32` y se cuenta la instrucción. Cada grupo de instrucciones se explica a continuación.

## 6. Las instrucciones, por grupo

### 6.1 ALU: aritmética y lógica (`add`, `addi`, …)

**Qué son.** Instrucciones que hacen una cuenta con dos valores y guardan el resultado en un registro. Hay dos familias:

```asm
add  x3, x1, x2      # tipo R: x3 = x1 + x2        (dos registros)
addi x3, x1, 10      # tipo I: x3 = x1 + 10        (un registro y un número fijo, el inmediato)
```

`add` y `addi` hacen **la misma operación**: cambia solo de dónde sale el segundo operando. Por eso hay un solo diccionario `_ALU` con las 10 operaciones de las R, y `_ALU_INMEDIATO` dice qué operación usa cada I (`"addi": "add"`, `"slti": "slt"`, …). No existe `subi`: para restar se usa `addi` con un número negativo.

| Operación        | Qué calcula                        | Implementación                                 | Caso borde                                               |
| ---------------- | ---------------------------------- | ---------------------------------------------- | -------------------------------------------------------- |
| `add`            | a + b                              | `(a + b) & M`                                  | `0xFFFFFFFF + 1` → `0`                                   |
| `sub`            | a − b                              | `(a - b) & M`                                  | `0 - 1` → `0xFFFFFFFF`                                   |
| `and`/`or`/`xor` | bit a bit                          | `a & b`, `a \| b`, `a ^ b`                     | no necesitan máscara: el resultado nunca pasa de 32 bits |
| `sll`            | corre a la izquierda               | `(a << (b & 0x1F)) & M`                        | `1 << 33` corre 1: solo cuentan 5 bits                   |
| `srl`            | corre a la derecha, entran ceros   | `a >> (b & 0x1F)`                              | `0x80000000 >> 4` → `0x08000000`                         |
| `sra`            | corre a la derecha, entra el signo | `(sign_extend(a, 32) >> (b & 0x1F)) & M`       | `0x80000000 >> 4` → `0xF8000000`                         |
| `slt`            | 1 si a < b **con signo**           | `int(sign_extend(a, 32) < sign_extend(b, 32))` | `-1 < 1` → `1`                                           |
| `sltu`           | 1 si a < b **sin signo**           | `int(a < b)`                                   | `0xFFFFFFFF < 1` → `0`                                   |

(`M` es `_MASCARA_32`.)

- **Los shifts usan 5 bits.** 2⁵ = 32: correr 32 lugares o más no tiene sentido en un registro de 32 bits.
- **El inmediato.** `decode_i` lo da con signo (en `addi x1, x0, -1`, `imm = -1`). Antes de pasarlo a la ALU se convierte a sin signo con `imm & M`.
- **`srai` sin código extra.** En `srai` el campo inmediato no vale solo el corrimiento: lleva el funct7 en los bits altos (`srai x1, x1, 4` tiene `imm = 0x404`). El `& 0x1F` de la ALU descarta esos bits.

**`x0` siempre vale 0.** Toda escritura pasa por `_escribir(rd, valor)`, que no hace nada si `rd == 0`. `addi x0, x0, 5` no cambia nada; por eso `addi x0, x0, 0` es el `nop`.

### 6.2 Loads y stores: la memoria (`lw`, `sw`, `lb`, …)

**Qué son.** Las únicas instrucciones que tocan la memoria de datos. Todas las demás trabajan solo con registros: es una arquitectura _load/store_.

```asm
lw x5, 8(x1)     # load:  x5 ← memoria[x1 + 8]      (x5 es el destino, rd)
sw x5, 8(x1)     # store: memoria[x1 + 8] ← x5      (x5 es la fuente, rs2)
```

`8(x1)` se lee "8 bytes después de la dirección que tiene `x1`": `x1` es la **base** y `8` el **offset**. Cada instrucción mueve 1, 2 o 4 bytes, y se describen con dos tablas:

```python
_LOADS  = {"lb": (1, True), "lh": (2, True), "lw": (4, False), "lbu": (1, False), "lhu": (2, False)}
_STORES = {"sb": 1, "sh": 2, "sw": 4}
```

`_LOADS` dice cuántos bytes lee cada load y si **extiende el signo**. `lw` va con `False` porque ya trae 32 bits. Los stores no tienen versión sin signo porque, al guardar, simplemente se cortan los bytes bajos del registro.

**Little-endian.** El byte menos significativo va en la dirección más baja (ADR-018). Con `x2 = 0x12345680` y `sw x2, 0(x1)`, con `x1 = 0x10`:

```txt
dirección:  0x10  0x11  0x12  0x13
byte:        80    56    34    12
```

| Load            | Bytes que lee | Valor        | Extensión                | Queda en el registro |
| --------------- | ------------- | ------------ | ------------------------ | -------------------- |
| `lw x3, 0(x1)`  | 80 56 34 12   | `0x12345680` | —                        | `0x12345680`         |
| `lb x3, 0(x1)`  | 80            | `0x80`       | de signo: el bit 7 es 1  | `0xFFFFFF80` (−128)  |
| `lbu x3, 0(x1)` | 80            | `0x80`       | con ceros                | `0x00000080` (128)   |
| `lh x3, 2(x1)`  | 34 12         | `0x1234`     | de signo: el bit 15 es 0 | `0x00001234`         |

**Algoritmo de la dirección (`_direccion`)**

```python
direccion = (base + imm) & M            # x1 + 8, en 32 bits
alineada  = direccion & ~(n - 1)        # n = 4 borra 2 bits; n = 2 borra 1; n = 1 no borra nada
if alineada != direccion: advertencia   # "0x008: lw desalineado en 0x011, se accede a 0x010"
return alineada % len(dmem)             # fuera de la DMEM da la vuelta: 0x410 → 0x010
```

- **Desalineados (ADR-018).** Una palabra empieza en un múltiplo de 4 y una media palabra en un múltiplo de 2. El hardware **no da error** con un acceso desalineado: ignora los bits bajos. El modelo hace lo mismo y deja una advertencia. `~(n - 1)` resuelve los tres tamaños con una sola fórmula, y por eso un acceso de un byte nunca está desalineado.
- **La vuelta.** Una dirección negativa también da la vuelta: `sw x2, -4(x0)` escribe en `0x3FC`.

**Load.** Lee con `int.from_bytes(dmem[d:d+n], "little")`. Si corresponde, extiende el signo con `sign_extend(valor, 8 * n)` y aplica la máscara. Escribe el resultado en `rd`.

**Store.** Corta `regs[rs2]` a `n` bytes (`& 0xFF`, `& 0xFFFF` o `& 0xFFFFFFFF`) y los escribe con `.to_bytes(n, "little")`. Después agrega `d & ~3` a `mem_escrita`.

**Memoria usada (ADR-008).** Todo store marca **la palabra entera** donde escribió: un `sb` en `0x13` marca `0x10`. Es lo mismo que hace el hardware, que tiene un bit por palabra. Los loads no marcan nada, y dos stores a la misma palabra la cuentan una sola vez.

### 6.3 Saltos y `lui`

**Qué son.** Normalmente el PC avanza de a 4. Un **salto** cambia la próxima instrucción; sin saltos no existirían los `if`, los loops ni las funciones.

| Instrucción              | ¿Cuándo salta?  | ¿A dónde?          | Guarda en `rd` |
| ------------------------ | --------------- | ------------------ | -------------- |
| `beq rs1, rs2, etiqueta` | si `rs1 == rs2` | `pc + offset`      | —              |
| `bne rs1, rs2, etiqueta` | si `rs1 != rs2` | `pc + offset`      | —              |
| `jal rd, etiqueta`       | siempre         | `pc + offset`      | `pc + 4`       |
| `jalr rd, imm(rs1)`      | siempre         | `(rs1 + imm) & ~1` | `pc + 4`       |

**El offset es relativo a la instrucción del salto.** En el assembly se escribe una etiqueta, pero en la palabra el ensamblador guarda la **distancia en bytes**. `decode_b` y `decode_j` la devuelven ya con signo.

```asm
0x04:  loop: addi x5, x5, -1
0x08:        bne  x5, x0, loop     # offset = 0x04 - 0x08 = -4  →  salta a 0x08 + (-4) = 0x04
```

El offset se suma al PC **del `bne`** (`0x08`), no a PC + 4. Los branches usan `_BRANCHES = {"beq": operator.eq, "bne": operator.ne}`. Como comparan igualdad, el signo no importa.

**Funciones con `jal` y `jalr`.** "Link" quiere decir que guardan la dirección de vuelta en `rd`:

```asm
0x00:  jal  x1, funcion     # x1 = 0x04 y salta: llamar a la función
0x04:  halt                 # acá se vuelve
0x20:  funcion: ...
0x24:  jalr x0, 0(x1)       # salta a x1 = 0x04: el return. rd = x0 descarta la vuelta
```

- **`jalr` es indirecto.** El destino sale de un **registro**, no de la instrucción.
- **El `& ~1`** borra el bit 0 del destino: `jalr x1, 5(x0)` salta a `4`. Es una regla de RISC-V.
- **Orden en `jalr`.** El destino se calcula **antes** de escribir `rd`. En `jalr x1, 0(x1)` los dos son el mismo registro, y escribir primero haría saltar a la dirección equivocada.
- **`jal x0, etiqueta`** es un salto simple, sin guardar nada: el `goto`.

**`lui` (_load upper immediate_).** Pone un número de 20 bits en la parte alta del registro, para cargar constantes grandes en dos pasos:

```asm
lui  x5, 0x12345        # x5 = 0x12345000
addi x5, x5, 0x678      # x5 = 0x12345678
```

`decode_u` ya devuelve `imm = 0x12345000`, así que la instrucción es "escribir `imm` en `rd`".

**PC fuera de rango.** `pc + offset` puede dar negativo (un `jal` a −4 desde 0). La máscara del final lo deja en `0xFFFFFFFC`, y el fetch lo lee como la última palabra de la IMEM.

## 7. `run()` y `estado_final()`

```python
def run(self, max_instr):
    for _ in range(max_instr):
        motivo = self.step()
        if motivo is not None:
            return motivo          # HALTED o ILLEGAL
    self.motivo = Motivo.TIMEOUT
    return Motivo.TIMEOUT
```

| Motivo    | Cuándo                                           | ¿Existe en el hardware?                                                     |
| --------- | ------------------------------------------------ | --------------------------------------------------------------------------- |
| `HALTED`  | se ejecutó `halt`                                | sí (`Motivo.HALTED` del protocolo)                                          |
| `ILLEGAL` | se buscó una palabra ilegal; el PC queda en ella | sí (`Motivo.ILLEGAL`)                                                       |
| `TIMEOUT` | pasaron `max_instr` pasos sin terminar           | no: es el corte del simulador para que un loop infinito no lo cuelgue (AC2) |

- **El conteo.** `max_instr` cuenta pasos, incluido el del `halt`. `instrucciones_retiradas` no cuenta ni el `halt` ni la ilegal.
- **Volver a llamar.** Llamar a `run()` después de terminar devuelve el mismo motivo, porque el PC sigue en el `halt` o la ilegal.

`estado_final()` devuelve un `EstadoArquitectonico` inmutable con:

- `regs`, como tupla;
- `mem_usada`: `{dirección: palabra}` de las palabras de `mem_escrita`, **en orden creciente**, como el snapshot (ADR-017);
- `pc` y `motivo`.

Si el programa todavía no terminó, lanza `RuntimeError`.

## 8. El formato `.expected`

Lo escribe `rvsim --expect`. Lo leen `tb_core_programs.v` (US-210) y `verify_rtl.py` (US-305). Tiene una palabra hex de 8 dígitos por línea, así un testbench lo carga entero con `$readmemh`; los comentarios `//` se ignoran y van sin acentos.

| Posición  | Contenido                                                                                                       |
| --------- | --------------------------------------------------------------------------------------------------------------- |
| `[0]`     | motivo: `1` = HALTED, `2` = ILLEGAL (los códigos de `Motivo` del protocolo, los mismos que reporta el hardware) |
| `[1]`     | PC (con ILLEGAL, el de la instrucción ilegal)                                                                   |
| `[2..33]` | `x0` … `x31`                                                                                                    |
| `[34]`    | K: cantidad de palabras usadas                                                                                  |
| `[35..]`  | K pares dirección, dato, en orden creciente                                                                     |

Ejemplo (`loop.asm`, que suma 1 + … + 10 y guarda 55 en `0x20`):

```txt
// estado esperado (golden model, US-108): una palabra por linea, para $readmemh
00000001  // motivo: HALTED
00000018  // PC
00000000  // x0
00000000  // x1
00000037  // x2
...
00000001  // palabras usadas
00000020  // direccion
00000037  // dato
```

- **TIMEOUT no se escribe.** Un programa que no termina no tiene resultado esperado: `a_expected` da `ValueError` y la CLI sale con error.
- **Ida y vuelta.** `leer_expected` es la inversa, y un test verifica que `leer_expected(a_expected(e)) == e` (AC6).
- **El PC no siempre se compara.** El PC del hardware al detenerse depende del pipeline, porque ya buscó instrucciones posteriores. US-210 decide si lo compara.

## 9. La CLI: `rvsim`

Desde `TP3/tools/`:

```bash
uv run python -m riscv_toolkit sim programa.asm                       # resumen
uv run python -m riscv_toolkit sim programa.asm --dump                # registros y memoria usada
uv run python -m riscv_toolkit sim programa.asm --expect p.expected   # para los testbenches
uv run python -m riscv_toolkit sim programa.asm --max-instr 1000      # otro límite (por defecto 100 000)
```

```txt
tests\iss\fixtures\loop.asm: HALTED en 0x018, 33 instrucciones
x0  = 0x00000000   x1  = 0x00000000   x2  = 0x00000037   x3  = 0x00000000
...
memoria usada (1 palabras):
  0x020: 0x00000037
```

- **Advertencias.** Las del ensamblador y las del modelo van a stderr.
- **Código de salida 0** si el programa terminó: HALTED o ILLEGAL. Una ilegal es un resultado válido; hay programas de prueba que la buscan a propósito.
- **Código de salida 1** ante un error de ensamblado, un error de archivo o un TIMEOUT. Con TIMEOUT no se escribe el `.expected`.

## 10. Entrada, desensamblado y comparación con el hardware

### 10.1 Qué recibe: palabras, no la `Imagen` ni bytes

El modelo recibe **solo la lista de palabras**: `GoldenModel(imagen.palabras)`. Es una lista de enteros de 32 bits, uno por instrucción:

```python
imagen.palabras   # [0x00A00293, 0xFFF28293, 0xFE029EE3, 0x0000000B]
```

El resto de la `Imagen` del ensamblador (`simbolos`, `mapa_lineas`, `expansiones`, `advertencias`) relaciona las palabras con el texto fuente. Lo usan el `.lst` y la GUI; para ejecutar no hace falta, y por el AC4 el modelo no depende del ensamblador.

El mismo programa existe en tres formas:

| Forma                  | Ejemplo             | Quién la usa                              |
| ---------------------- | ------------------- | ----------------------------------------- |
| texto                  | `addi x5, x0, 10`   | quien programa, el ensamblador            |
| palabras (`list[int]`) | `[0x00A00293, ...]` | el golden model, `$readmemh` (vía `.hex`) |
| bytes                  | `93 02 A0 00 ...`   | el `.bin` y el comando `LOAD` por UART    |

`FakeTransport` (US-409) va a recibir **bytes** del protocolo y los va a pasar a palabras con `int.from_bytes(..., "little")` antes de crear el modelo.

### 10.2 Decodificar no es desensamblar

- **Decodificar:** sacar los campos de la palabra (opcode, `rd`, `rs1`, `imm`…) para **ejecutarla**. Lo hacen `identificar` y los `decode_*` dentro de `step()`, y el resultado son números. Es el equivalente a la Control Unit y el `imm_gen` del hardware.
- **Desensamblar:** convertir la palabra en **texto para humanos** (`addi x5, x0, 10`). Lo hace `desensamblar()` en `disasm/` (US-107), y lo usan la GUI y los listados.

Los dos comparten `identificar` y los `decode_*`, pero el modelo nunca genera texto.

### 10.3 `step()` frente al hardware: mismo resultado, distinto mecanismo

Cada parte de `step()` tiene su equivalente en una etapa del pipeline:

| `step()`                             | Hardware                                             | Etapa                              |
| ------------------------------------ | ---------------------------------------------------- | ---------------------------------- |
| `imem[(pc // 4) % len]`              | IMEM indexada con `pc[9:2]`                          | IF                                 |
| `identificar` + `decode_*`           | Control Unit + `imm_gen`                             | ID                                 |
| `self.regs[rs1]`, `self.regs[rs2]`   | lectura del banco de registros                       | ID                                 |
| `_ALU[...]`                          | ALU + ALU control                                    | EX                                 |
| `_BRANCHES` y el cálculo del destino | `branch_cmp` + sumador del destino                   | EX (branches y `jalr`), ID (`jal`) |
| `self.dmem[...]` en loads y stores   | DMEM                                                 | MEM                                |
| `_escribir(rd, ...)`                 | escritura del banco de registros (`x0` cableado a 0) | WB                                 |
| `siguiente`                          | mux del próximo PC                                   | IF                                 |
| `mem_escrita`                        | bitmap de memoria usada (ADR-008)                    | Debug Unit                         |

**La diferencia de fondo.** El ISS completa las 5 etapas de una instrucción **antes de empezar la siguiente**. El hardware tiene **hasta 5 instrucciones a la vez**, cada una en una etapa. De ahí sale todo lo que el hardware agrega:

- **Latches entre etapas** (IF/ID, ID/EX, EX/MEM, MEM/WB): guardan el estado de cada instrucción en vuelo.
- **Forwarding.** Con `add x1, x2, x3` seguido de `sub x4, x1, x5`, el ISS lee `regs[1]` ya actualizado. En el hardware, `x1` todavía no llegó a WB cuando `sub` está en EX, así que el valor se adelanta desde EX/MEM.
- **Stall por load-use.** Si una instrucción usa el dato de un `lw` justo anterior, tiene que esperar un ciclo, porque el dato recién existe al final de MEM. En el ISS el `lw` ya terminó.
- **Flush.** El hardware supone que el branch no se toma y sigue buscando instrucciones; si se toma, descarta las que buscó de más. El ISS nunca busca de más, porque sabe el próximo PC antes del fetch.
- **Ilegales especulativas.** Una palabra ilegal buscada después de un branch tomado se descarta y no detiene nada (ADR-018). En el ISS no puede pasar: solo hace fetch de lo que se ejecuta.
- **HALT con vaciado.** El hardware deja terminar las instrucciones más viejas que siguen en el pipeline antes de detenerse.
- **Ciclos contra instrucciones.** El hardware cuenta ciclos y el ISS cuenta instrucciones. El cociente es el CPI, que es mayor a 1 por los stalls y los flushes.
- **La Debug Unit:** clock enable, modo paso a paso y snapshot por UART.

**Lo que tiene el ISS y el hardware no:**

- **TIMEOUT:** en la placa, un loop infinito sigue hasta un `ABORT`.
- **Advertencias de accesos desalineados:** el hardware ignora los bits bajos en silencio.

Por eso sirve de referencia: si, con todos esos mecanismos, el pipeline llega al **mismo estado final** que el ISS, los riesgos están bien resueltos. Si un forwarding falla, algún registro queda distinto y la comparación lo detecta.

## 11. Decisiones de diseño

### 11.1 `identificar` se comparte con el desensamblador

Estaba como función privada en `disasm/`. Se movió a `isa/instrucciones.py` para que el ISS y el desensamblador rechacen exactamente las mismas palabras.

- **Alternativa: importarla privada.** Acopla el ISS al desensamblador.
- **Alternativa: duplicarla.** Las dos copias podrían divergir.

### 11.2 `Motivo` propio, con TIMEOUT

El protocolo ya tiene un `Motivo` (`NINGUNO`, `HALTED`, `ILLEGAL`, `ABORTED`), pero TIMEOUT no existe en el hardware. Agregarlo al protocolo filtraría un concepto del simulador a los bytes de la UART. `expected.py` traduce de un `Motivo` al otro.

### 11.3 Una tabla por grupo de instrucciones

`_ALU`, `_ALU_INMEDIATO`, `_LOADS`, `_STORES` y `_BRANCHES` reemplazan un `if` por instrucción. Las 33 instrucciones se resuelven con ocho ramas en `step()`, y agregar una instrucción es agregar una entrada. Es la misma idea que el hardware: una ALU con un selector de operación.

- **Alternativa:** un `match` con 33 casos. Es más largo y repite el patrón "leer operandos, operar, escribir".

### 11.4 Registros sin signo

Se guardan como `0 … 2³² − 1` y se convierten con signo solo donde hace falta. Coincide con el snapshot y con el `.expected`, que comparan bits.

- **Alternativa: guardarlos con signo.** Obliga a convertir en cada comparación con el hardware.

### 11.5 La ilegal no toca nada

`step()` devuelve `ILLEGAL` sin mover el PC. Así el PC del estado final es el de la instrucción ilegal (AC2), y llamar a `run()` otra vez es inofensivo.

### 11.6 Advertencias como lista

`advertencias: list[str]`, como `Imagen.advertencias` del ensamblador. Es fácil de testear y la CLI la imprime en stderr.

- **Alternativa: `warnings` o `logging`.** Es más difícil de leer en los tests y mezcla la salida con la de otras bibliotecas.

### 11.7 `.expected` para `$readmemh`

Una palabra por línea con un layout fijo: el testbench lo carga en una línea y lee posiciones conocidas.

- **Alternativa: texto `clave = valor`.** Se lee más fácil, pero parsearlo en Verilog con `$fscanf` es frágil.

## 12. Cómo se valida

| Archivo                          | Qué prueba                                                                                                                                                                                                                                                                                                                         |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/iss/test_golden_model.py` | estado inicial, relleno con HALT y validaciones (T1); las 19 instrucciones de la ALU con valores borde (AC1); loads y stores, little-endian, desalineados (AC5), memoria usada (AC3) y la vuelta de las direcciones; branches, funciones con `jal`/`jalr`, `jalr` impar y `lui`; TIMEOUT e ILLEGAL con su PC (AC2); `estado_final` |
| `tests/iss/fixtures/*.asm`       | cuatro programas con el resultado calculado a mano en los comentarios: `aritmetica`, `loads_stores`, `branches` y `loop`                                                                                                                                                                                                           |
| `tests/iss/test_expected.py`     | ida y vuelta y layout del `.expected` (AC6); errores de formato                                                                                                                                                                                                                                                                    |
| `tests/cli/test_rvsim.py`        | `--dump`, `--expect`, códigos de salida, advertencias y errores                                                                                                                                                                                                                                                                    |

La suite completa, con programas que verifican su propia firma en `0x3FC`, llega en US-304.

## 13. Preguntas de autoevaluación

> [!NOTE]
> **¿Por qué el golden model no modela el pipeline?**:
>
> Porque es la referencia de **qué** tiene que pasar, no de **cómo**. Un pipeline correcto llega al mismo estado final que la ejecución de a una instrucción. Si el ISS modelara el pipeline, un error de diseño compartido (por ejemplo, un forwarding mal entendido) aparecería en los dos y la comparación no lo detectaría.
> [!NOTE]
> **¿Por qué `sub` necesita `& _MASCARA_32` y `xor` no?**
>
> `0 - 1` da `-1` en Python, que no es un valor de 32 bits sin signo; con la máscara queda `0xFFFFFFFF`. `xor` de dos números de 32 bits nunca tiene bits por encima del 31 ni da negativo.
> [!NOTE]
> **El byte `0x80` está en memoria. ¿Qué dejan `lb` y `lbu` en el registro?**
>
> `lb` extiende el signo: el bit 7 es 1, así que rellena con unos y deja `0xFFFFFF80` (−128). `lbu` rellena con ceros y deja `0x00000080` (128).
> [!NOTE]
> **¿Por qué un `sb` marca en `mem_escrita` la palabra entera?**
>
> Porque el hardware lleva un bit por **palabra** (ADR-008) y el snapshot manda palabras completas. El ISS tiene que marcar lo mismo para que la comparación de memoria usada coincida.
> [!NOTE]
> **¿A qué dirección salta `bne` si el modelo sumara el offset a PC + 4?**
>
> Cuatro bytes más adelante de lo que corresponde: un loop saltaría a la segunda instrucción del cuerpo y se saltearía la primera en cada vuelta.
> [!NOTE]
> **¿Qué pasa con `jalr x1, 0(x1)` si se escribe `rd` antes de calcular el destino?**
>
> `x1` pasa a valer PC + 4 y el salto va ahí, a la instrucción siguiente, en lugar de a la dirección que tenía `x1`. Por eso el destino se calcula primero.
> [!NOTE]
> **¿Por qué TIMEOUT no se escribe en el `.expected`?**
>
> Porque no es un resultado del programa sino un corte del simulador. El hardware no tiene ese estado: un loop infinito en la placa sigue corriendo hasta el `ABORT`.
