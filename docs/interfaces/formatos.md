# Formatos de Instrucción: Campos y Bits

- **Versión:** 0.1
- **Fecha:** 2026-10-25
- **Historia:** US-105
- **La implementan:** `tools/riscv_toolkit/isa/formatos.py` (software) y `hw/rtl/core/imm_gen.v` (hardware)

Este documento fija **en qué bits de la palabra va cada campo** y **cómo se arma el inmediato** en cada formato. Es el contrato entre `formatos.py` y `imm_gen.v`: los dos tienen que reordenar los bits exactamente igual (US-203, AC2 los compara). Qué opcode, `funct3` y `funct7` tiene cada instrucción está en la PRD §2.2 y en `isa/instrucciones.py`.

## 1. Notación

- `[31:25]` son los bits 31 a 25 de la palabra (el 31 es el más significativo).
- `imm[12|10:5]` quiere decir "el bit 12 del inmediato, seguido de los bits 10 a 5". Se lee de izquierda a derecha, en el mismo orden en que aparecen en la palabra.
- **Posición** es el número del bit más bajo del campo: es cuánto se desplaza con `<<` al codificar y con `>>` al decodificar.

## 2. Campos fijos

Estos campos están **siempre en el mismo lugar**, en todos los formatos que los tienen. Eso le permite al hardware leer los registros en ID antes de saber qué instrucción es.

| Campo    | Bits      | Posición | Ancho | Rango   | Lo tienen        |
| -------- | --------- | -------- | ----- | ------- | ---------------- |
| `opcode` | `[6:0]`   | 0        | 7     | 0 – 127 | todos            |
| `rd`     | `[11:7]`  | 7        | 5     | 0 – 31  | R, I, U, J       |
| `funct3` | `[14:12]` | 12       | 3     | 0 – 7   | R, I, S, B       |
| `rs1`    | `[19:15]` | 15       | 5     | 0 – 31  | R, I, S, B       |
| `rs2`    | `[24:20]` | 20       | 5     | 0 – 31  | R, S, B          |
| `funct7` | `[31:25]` | 25       | 7     | 0 – 127 | R (y shifts de I) |

Lo único que cambia de lugar entre formatos es el **inmediato**.

## 3. Los seis formatos

```txt
 31        25 24   20 19   15 14  12 11         7 6       0
┌────────────┬───────┬───────┬──────┬────────────┬─────────┐
│   funct7   │  rs2  │  rs1  │funct3│     rd     │ opcode  │  R
├────────────┴───────┼───────┼──────┼────────────┼─────────┤
│     imm[11:0]      │  rs1  │funct3│     rd     │ opcode  │  I
├────────────┬───────┼───────┼──────┼────────────┼─────────┤
│ imm[11:5]  │  rs2  │  rs1  │funct3│  imm[4:0]  │ opcode  │  S
├────────────┼───────┼───────┼──────┼────────────┼─────────┤
│imm[12|10:5]│  rs2  │  rs1  │funct3│imm[4:1|11] │ opcode  │  B
├────────────┴───────┴───────┴──────┼────────────┼─────────┤
│            imm[31:12]             │     rd     │ opcode  │  U
├───────────────────────────────────┼────────────┼─────────┤
│      imm[20|10:1|11|19:12]        │     rd     │ opcode  │  J
└───────────────────────────────────┴────────────┴─────────┘
```

**Por qué el inmediato está desordenado en S, B y J:** para que `rs1`, `rs2` y `rd` no se muevan nunca, y para que el **bit de signo del inmediato sea siempre el bit 31** de la palabra. Así `imm_gen` extiende el signo copiando siempre el mismo cable. El costo lo paga el software, que tiene que reordenar los bits.

### 3.1 R — registro a registro (`add`, `sub`, `sll`, …)

No tiene inmediato. Los seis campos son los de la sección 2.

| Ejemplo          | Palabra      |
| ---------------- | ------------ |
| `add x3, x1, x2` | `0x002081B3` |
| `sub x5, x6, x7` | `0x407302B3` |

### 3.2 I — inmediato, loads y `jalr` (`addi`, `lw`, `jalr`, …)

| Bits de la palabra | Bits del inmediato |
| ------------------ | ------------------ |
| `[31:20]`          | `imm[11:0]`        |

- **Inmediato:** 12 bits con signo, de **−2048 a 2047**. Se extiende el signo desde el bit 11.
- **Shifts con inmediato** (`slli`, `srli`, `srai`): los 12 bits se reparten en `funct7` (`[31:25]`) y `shamt` (`[24:20]`, de 0 a 31). En software se codifican con el formato I normal, con `imm = (funct7 << 5) | shamt`. El ensamblador valida `shamt` (US-106).

| Ejemplo            | Inmediato                    | Palabra      |
| ------------------ | ---------------------------- | ------------ |
| `addi x1, x0, 5`   | 5                            | `0x00500093` |
| `addi x1, x0, -1`  | −1 (`0xFFF`)                 | `0xFFF00093` |
| `lw x5, -4(x2)`    | −4 (`0xFFC`)                 | `0xFFC12283` |
| `srai x1, x2, 3`   | `(0b0100000 << 5) \| 3` = 1027 | `0x40315093` |

### 3.3 S — stores (`sb`, `sh`, `sw`)

| Bits de la palabra | Bits del inmediato |
| ------------------ | ------------------ |
| `[31:25]`          | `imm[11:5]`        |
| `[11:7]`           | `imm[4:0]`         |

- **Inmediato:** 12 bits con signo, de **−2048 a 2047**. Es el mismo número que en I, pero partido en dos, porque en `[11:7]` no hay `rd` (un store no escribe registros) y en `[24:20]` va `rs2` (el dato a guardar).

| Ejemplo         | Palabra      |
| --------------- | ------------ |
| `sw x1, 0(x0)`  | `0x00102023` |
| `sw x5, -4(x2)` | `0xFE512E23` |

### 3.4 B — branches (`beq`, `bne`)

| Bits de la palabra | Bits del inmediato |
| ------------------ | ------------------ |
| `[31]`             | `imm[12]` (signo)  |
| `[30:25]`          | `imm[10:5]`        |
| `[11:8]`           | `imm[4:1]`         |
| `[7]`              | `imm[11]`          |

- **Inmediato:** es el offset en bytes desde el PC del branch. Tiene 13 bits con signo, de **−4096 a 4094**, y **siempre es par**.
- **`imm[0]` no se guarda**, porque siempre vale 0. Por eso un offset impar no se puede codificar, y `encode_b` lo rechaza (US-105, AC3).
- **El bit 11 va al bit 7 de la palabra**, el lugar que en S ocupa `imm[0]`. Así, `imm[10:5]` y `imm[4:1]` quedan en las mismas posiciones que en S.

| Ejemplo            | Palabra      |
| ------------------ | ------------ |
| `beq x0, x0, -4`   | `0xFE000EE3` |
| `bne x1, x2, 8`    | `0x00209463` |

### 3.5 U — `lui`

| Bits de la palabra | Bits del inmediato |
| ------------------ | ------------------ |
| `[31:12]`          | `imm[31:12]`       |

- **Inmediato:** se trabaja con el **valor de 32 bits** que queda en el registro, con los 12 bits bajos en 0, sin signo: de `0x00000000` a `0xFFFFF000`.
- **Del assembly al valor:** el ensamblador traduce `lui x1, 0x12345` a `imm = 0x12345 << 12`.
- **Valor con bits bajos:** si los 12 bits bajos no son 0, `encode_u` lo rechaza.

| Ejemplo           | Palabra      |
| ----------------- | ------------ |
| `lui x1, 0x12345` | `0x123450B7` |

### 3.6 J — `jal`

| Bits de la palabra | Bits del inmediato |
| ------------------ | ------------------ |
| `[31]`             | `imm[20]` (signo)  |
| `[30:21]`          | `imm[10:1]`        |
| `[20]`             | `imm[11]`          |
| `[19:12]`          | `imm[19:12]`       |

- **Inmediato:** es el offset en bytes desde el PC del `jal`. Tiene 21 bits con signo, de **−1048576 a 1048574** (±1 MiB), y **siempre es par**. Igual que en B, `imm[0]` no se guarda.
- **`imm[19:12]` queda en su propio lugar** (`[19:12]`), igual que en U. Eso le ahorra cables a `imm_gen`.

| Ejemplo         | Palabra      |
| --------------- | ------------ |
| `jal x0, 0`     | `0x0000006F` |
| `jal x1, 2048`  | `0x001000EF` |
| `jal x1, -4`    | `0xFFDFF0EF` |

### 3.7 HALT (ADR-004)

No es un formato con campos: es la palabra fija **`0x0000000B`** (`HALT_WORD`), y el hardware la detecta **solo por el opcode** `0001011` (`HALT_OPCODE`). Por eso `formatos.py` no tiene `encode_halt` ni `decode_halt`:
- el ensamblador escribe `HALT_WORD`;
- el desensamblador y el golden model comparan `palabra & 0x7F` con `HALT_OPCODE`.

Las dos constantes están en `isa/instrucciones.py`.

## 4. Convenciones de `formatos.py`

- **Un dataclass por formato:** `CamposR`, `CamposI`, `CamposS`, `CamposB`, `CamposU` y `CamposJ`, con `encode_x(campos) -> int` y `decode_x(palabra) -> CamposX`. Para cualquier palabra válida, `decode_x(encode_x(c)) == c`.
- **El inmediato siempre es el valor real, no el campo crudo:**
  - en I, S, B y J es un entero con signo (−1 es `-1`, no `0xFFF`);
  - en B y J es el offset en bytes, incluido el bit 0;
  - en U es el valor de 32 bits sin signo.
- **`encode_*` valida todos los campos** antes de armar la palabra, y lanza `ErrorCodificacion` (subclase de `ValueError`) con el nombre del campo, el valor y el rango.

  **Por qué:** en Python un número que no entra en su campo no se trunca, sino que **pisa** el campo de al lado. Por ejemplo, `rd = 32` pondría un 1 en el bit 12, que es parte de `funct3`.
- **Inmediatos negativos:** antes de repartir sus bits se enmascaran al ancho del formato (`imm & 0xFFF`, `& 0x1FFF` o `& 0x1FFFFF`). En Python, `-1` tiene "infinitos" unos a la izquierda.
- **Al decodificar**, cada pedazo se extrae con `_campo(palabra, posición, ancho)`, se rearma el inmediato y se le extiende el signo con `sign_extend`.
