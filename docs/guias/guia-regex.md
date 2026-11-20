# Guía de expresiones regulares (US-106)

Qué es una expresión regular, cómo se usa en Python y cómo funciona la del lexer del ensamblador (`TP3/tools/riscv_toolkit/assembler/lexer.py`). Para el ensamblador en general, ver [guia-ensamblador.md](guia-ensamblador.md).

## Parte 1: expresiones regulares en general

### 1.1 Qué son y para qué sirven

Una **expresión regular** (regex, de _regular expression_) es un patrón que describe un conjunto de textos. En vez de escribir a mano "leé un carácter, si es una `x` fijate si lo que sigue son dígitos…", se escribe `x[0-9]+` y el motor de regex hace ese recorrido.

### 1.2 Piezas básicas

| Pieza   | Significa                                                        | Ejemplo          | Encaja con              |
| ------- | ---------------------------------------------------------------- | ---------------- | ----------------------- |
| `abc`   | Esos caracteres, en ese orden                                    | `addi`           | `addi`                  |
| `.`     | Cualquier carácter (salvo salto de línea)                        | `x.`             | `x5`, `xa`, `x,`        |
| `[...]` | **Clase**: uno de los caracteres del conjunto                    | `[abc]`          | `a`, `b` o `c`          |
| `[a-z]` | Rango dentro de una clase                                        | `[0-9A-Fa-f]`    | un dígito hexadecimal   |
| `\s`    | Un espacio en blanco (espacio, tab, `\r`, `\n`)                  | `\s+`            | `"   "`, `"\t"`         |
| `\d`    | Un dígito (en Python también los Unicode, como `٣`)              | `\d`             | `7`                     |
| `\`     | **Escape**: el carácter siguiente pierde su significado especial | `\.`, `\(`, `\#` | `.`, `(`, `#` literales |

### 1.3 Cuantificadores: cuántas veces

| Cuantificador | Significa            | Ejemplo      | Encaja con  |
| ------------- | -------------------- | ------------ | ----------- |
| `?`           | 0 o 1 vez (opcional) | `-?[0-9]`    | `5`, `-5`   |
| `*`           | 0 o más              | `[a-z]*`     | `""`, `nop` |
| `+`           | 1 o más              | `[0-9]+`     | `7`, `2047` |
| `{n,m}`       | Entre n y m veces    | `[0-9]{1,3}` | `7`, `255`  |

Los cuantificadores son **codiciosos** (_greedy_): toman todo lo que pueden. `[0-9]+` sobre `a12b345` encuentra `12` y `345`, no `1`, `2`, `3`…

### 1.4 Alternativas y grupos

| Pieza             | Significa                                                   | Ejemplo                     |
| ----------------- | ----------------------------------------------------------- | --------------------------- |
| `A\|B`            | **Alternativa**: A o B                                      | `beq\|bne`                  |
| `(...)`           | **Grupo con captura**: agrupa y además guarda lo que encajó | `(x[0-9]+)`                 |
| `(?:...)`         | **Grupo sin captura**: solo agrupa                          | `-?(?:0x[0-9a-f]+\|[0-9]+)` |
| `(?P<nombre>...)` | **Grupo con nombre**: captura y se consulta por nombre      | `(?P<REGISTRO>x[0-9]+)`     |

**Las alternativas se prueban de izquierda a derecha y gana la primera que encaja, no la más larga:**

```python
re.search(r"a|ab", "ab").group()   # 'a'
re.search(r"ab|a", "ab").group()   # 'ab'
```

Esto es clave para el lexer (ver 2.3).

¿Por qué existe el grupo sin captura? Porque los grupos con captura cambian lo que devuelven algunas funciones:

```python
re.findall(r"-?(0x[0-9A-Fa-f]+|[0-9]+)", "-4 0x1F 10")    # ['4', '0x1F', '10']  ← se perdió el '-'
re.findall(r"-?(?:0x[0-9A-Fa-f]+|[0-9]+)", "-4 0x1F 10")  # ['-4', '0x1F', '10']
```

### 1.5 Anclas: posiciones, no caracteres

| Ancla     | Significa                                                                                                     |
| --------- | ------------------------------------------------------------------------------------------------------------- |
| `^` / `$` | Principio / fin del texto                                                                                     |
| `\b`      | **Límite de palabra**: entre un carácter de palabra (`[A-Za-z0-9_]`) y uno que no lo es, o el borde del texto |

Las anclas no consumen caracteres: solo exigen que en esa posición se cumpla algo.

```python
re.findall(r"x[0-9]+", "x5a x5")     # ['x5', 'x5']  ← encontró un 'x5' dentro de 'x5a'
re.findall(r"x[0-9]+\b", "x5a x5")   # ['x5']        ← entre '5' y 'a' no hay límite de palabra
```

### 1.6 Las regex en Python

```python
import re

patron = re.compile(r"x[0-9]+")   # se compila una vez y se reutiliza
```

- **`r"..."`** (_raw string_): Python no interpreta las `\`. Sin la `r`, `"\b"` sería el carácter _backspace_ y no el ancla. Escribí las regex siempre con `r`.
- **`re.compile`**: traduce el patrón a una estructura interna una sola vez. En el lexer se hace al importar el módulo, no por cada línea.

| Función                   | Qué hace                                                            |
| ------------------------- | ------------------------------------------------------------------- |
| `patron.match(texto)`     | ¿Encaja **al principio** del texto? Devuelve un `Match` o `None`    |
| `patron.fullmatch(texto)` | ¿Encaja con **todo** el texto?                                      |
| `patron.search(texto)`    | La **primera** coincidencia en cualquier posición                   |
| `patron.findall(texto)`   | Lista con todas las coincidencias (strings)                         |
| `patron.finditer(texto)`  | Iterador de objetos `Match`, uno por coincidencia (lo usa el lexer) |

Un objeto `Match` responde:

```python
m = re.match(r"(?P<nombre>[a-z]+):", "loop: nop")
m.group()          # 'loop:'   todo lo que encajó
m.group("nombre")  # 'loop'    solo el grupo
m.lastgroup        # 'nombre'  el nombre del último grupo que encajó
```

**Flag `re.VERBOSE`**: permite escribir la regex en varias líneas, con espacios y comentarios que el motor ignora. A cambio, un `#` o un espacio literal hay que escaparlos (`\#`, `\`).

### 1.7 Errores comunes

- **Olvidarse de escapar**: `.word` encaja con `xword`, porque el `.` es "cualquier carácter". Lo correcto es `\.word`.
- **Olvidarse la `r`** delante del string.
- **Ordenar mal las alternativas**: la más general adelante "tapa" a las más específicas.
- **Usar `match` creyendo que valida todo**: `re.match(r"[0-9]+", "12abc")` encaja (con `12`). Para validar todo el texto, `fullmatch`.
- **Regex ilegibles**: si una regex no se entiende en un minuto, conviene partirla o usar `VERBOSE` con comentarios.

## Parte 2: la regex del lexer

### 2.1 La idea: una regex con una alternativa por tipo de token

```python
_PATRON = re.compile(
    r"""
      (?P<COMENTARIO>\#.*)
    | (?P<ESPACIO>\s+)
    | (?P<ETIQUETA>[A-Za-z_][A-Za-z0-9_]*):
    | (?P<DIRECTIVA>\.[a-z]+)
    | (?P<REGISTRO>x[0-9]+)\b
    | (?P<INMEDIATO>-?(?:0x[0-9A-Fa-f]+|[0-9]+))\b
    | (?P<IDENTIFICADOR>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<COMA>,)
    | (?P<PAR_ABRE>\()
    | (?P<PAR_CIERRA>\))
    | (?P<OTRO>.)
    """,
    re.VERBOSE,
)
```

Cada alternativa es un **grupo con nombre**, y el nombre es el tipo de token. `finditer` recorre la línea: en cada posición prueba las alternativas en orden, toma la primera que encaja y sigue desde donde terminó. `m.lastgroup` dice cuál de ellas encajó, y `TipoToken[m.lastgroup]` lo convierte en el enum.

La última alternativa, `OTRO`, es `.`: encaja con cualquier carácter. Gracias a ella `finditer` nunca saltea nada; si se llega a `OTRO`, ese carácter no forma ningún token válido y el lexer lanza `ErrorEnsamblado`.

### 2.2 Cada alternativa

| Grupo                            | Regex                            | Lectura                                                                                                    | Encaja                        | No encaja                                                      |
| -------------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------- | -------------------------------------------------------------- |
| `COMENTARIO`                     | `\#.*`                           | Un `#` y todo lo que sigue hasta el fin de la línea                                                        | `# decrementa`                | —                                                              |
| `ESPACIO`                        | `\s+`                            | Uno o más blancos                                                                                          | `"  "`, `"\t"`                | —                                                              |
| `ETIQUETA`                       | `[A-Za-z_][A-Za-z0-9_]*:`        | Letra o `_`, después letras, dígitos o `_`, y `:` (fuera del grupo, así el texto queda sin los dos puntos) | `loop:`, `fin_2:`, `_aux:`    | `2loop:` (empieza con dígito), `loop :` (espacio antes de `:`) |
| `DIRECTIVA`                      | `\.[a-z]+`                       | Un punto literal y letras                                                                                  | `.word`                       | `word`                                                         |
| `REGISTRO`                       | `x[0-9]+\b`                      | `x`, uno o más dígitos, y límite de palabra                                                                | `x0`, `x31`, `x32`            | `xori`, `x5a`, `X5`                                            |
| `INMEDIATO`                      | `-?(?:0x[0-9A-Fa-f]+\|[0-9]+)\b` | Signo menos opcional y un número hexa o decimal                                                            | `-4`, `0x1F`, `-0x10`, `2047` | `- 1`, `12abc`, `0xZZ`                                         |
| `IDENTIFICADOR`                  | `[A-Za-z_][A-Za-z0-9_]*`         | Igual que la etiqueta, sin `:`                                                                             | `addi`, `nop`, `loop`, `ADDI` | `2x`                                                           |
| `COMA`, `PAR_ABRE`, `PAR_CIERRA` | `,` `\(` `\)`                    | Un solo carácter (los paréntesis escapados)                                                                | `,` `(` `)`                   | —                                                              |
| `OTRO`                           | `.`                              | Cualquier otro carácter → error                                                                            | `@`, `;`                      | —                                                              |

No hay ninguna regla especial para `loop`: **cualquier nombre** que cumpla el patrón es una etiqueta (`fin`, `Bucle_2`, `_aux`). En los tests aparece `loop` solo como ejemplo.

### 2.3 Por qué el orden importa

- **`ETIQUETA` antes que `IDENTIFICADOR`**: las dos empiezan igual. Si `IDENTIFICADOR` fuera primero, en `loop:` tomaría `loop`, y el `:` quedaría suelto y caería en `OTRO` (error).
- **`REGISTRO` antes que `IDENTIFICADOR`**: `x5` también cumple el patrón de identificador. Si el orden fuera el inverso, nunca habría tokens `REGISTRO`.
- **`OTRO` al final**: encaja con todo, así que adelante taparía a todas las demás.

### 2.4 Por qué los `\b`

- **En `REGISTRO`**: sin `\b`, en `x5a` encajaría `x5` y después `a` sería un identificador aparte: dos tokens donde el usuario escribió uno. Con `\b`, `REGISTRO` no encaja y el texto completo `x5a` se lee como `IDENTIFICADOR`; el parser después dice "se esperaba un registro".
- **En `INMEDIATO`**: sin `\b`, `12abc` daría `12` y `abc`. Con `\b` no encaja ningún número, el `1` cae en `OTRO`, y el error es "carácter inesperado '1'".

`xori` no tiene este problema: después de la `x` viene una `o`, que no es un dígito, así que `REGISTRO` no encaja desde el principio.

### 2.5 Qué decide el lexer y qué deja para el parser

El lexer **clasifica**, no valida el significado:

- `x32` es un `REGISTRO`; que no exista lo dice el parser contra `REGISTROS`, con el mensaje "registro inválido 'x32'".
- `ADDI` y `X5` son `IDENTIFICADOR`; el parser no los encuentra en `INSTRUCCIONES` ni en `REGISTROS`.
- `0xFFFFFFFF` es un `INMEDIATO`; si entra en el campo lo decide `isa/formatos.py`.
- El texto del inmediato se convierte a número en el parser: `int("-0x10", 16)` → `-16`, `int("010")` → `10`.

Así cada error se informa en la etapa que tiene contexto para explicarlo.
