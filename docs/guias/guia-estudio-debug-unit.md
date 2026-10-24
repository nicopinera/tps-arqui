# Guía de estudio: la FSM de la Debug Unit

Guía para entender **en qué estado está la Debug Unit (DU), qué hace en cada uno y por qué pasa al siguiente**. La referencia formal (bytes, códigos, tablas) está en [`protocolo.md`](protocolo.md). Esta guía cuenta la historia.

![FSM de la Debug Unit](diagramas/debug_unit_fsm.svg)

## 1. Qué es una FSM

Una **máquina de estados finitos** (_Finite State Machine_) es un circuito que en cada momento está en **uno** de un conjunto chico de estados. Un **evento** (llega un byte, el núcleo avisa que terminó) la hace **transicionar** a otro estado y, en el camino, ejecutar una **acción** (mandar un `ACK`, poner `i_enable = 1`).

En el diagrama, cada flecha se lee **`evento [condición] / acción`**. Por ejemplo, `RUN / ACK, i_enable = 1` quiere decir "llegó el comando RUN; respondo ACK y habilito el reloj del núcleo".

## 2. Los 7 estados en una línea

| Estado     | En una frase                                                         |
| ---------- | -------------------------------------------------------------------- |
| `IDLE`     | Estoy prendida, pero no tengo un programa válido                     |
| `LOADING`  | Estoy recibiendo un programa                                         |
| `READY`    | Tengo un programa limpio, listo para arrancar en el ciclo 0          |
| `RUN`      | El núcleo corre libre                                                |
| `STEPPING` | Estoy en medio de una ejecución paso a paso, con el núcleo congelado |
| `DUMPING`  | Estoy enviando un snapshot o un bloque de memoria                    |
| `HALTED`   | La ejecución terminó y el pipeline está vacío                        |

`LOADING` y `DUMPING` son **estados de paso**: la DU está ocupada recibiendo o enviando, no atiende comandos y sale sola cuando termina.

## 3. El cuento completo

### 3.1 Encendido → `IDLE`

Al prender la placa, o al apretar el botón de reset (`i_reset`), la DU arranca en `IDLE`. La IMEM no tiene nada confiable todavía, así que no se puede ejecutar: `RUN` y `STEP` responden `NACK(ERR_ESTADO)`. Lo que sí se puede hacer es `LOAD`, `RESET`, `DUMP`, `DUMP_MEM` y `PING`.

### 3.2 `LOAD`: `IDLE` → `LOADING`

La GUI manda el byte `'L'` (`0x4C`) y la DU pasa a `LOADING`.

**Qué viaja:** no el texto en assembly, sino el **código máquina ya ensamblado**. La PC corre el ensamblador y manda palabras de 32 bits (`addi x1, x0, 5` viaja como `93 00 50 00`). El orden es:

1. `N`: cuántas palabras vienen (2 bytes).
2. Las `N` palabras, 4 bytes cada una.
3. Un byte de checksum, que es el XOR de todo lo anterior salvo la `'L'`.

**¿Se verifica palabra por palabra o todo al final?** **Todo al final.** La DU escribe cada palabra en la IMEM **apenas termina de llegar** y va acumulando el XOR. Recién cuando llega el último byte compara su XOR con el checksum que mandó la PC. No hay verificación por instrucción: una sola suma de control para todo el programa.

> ¿Por qué no se guarda todo en un buffer y se escribe al final? Porque el buffer sería otra IMEM entera de flip-flops. Es más barato escribir directo y, si algo sale mal, "borrar" la IMEM rellenándola con HALT.

Mientras está en `LOADING`, **todo byte es parte de la carga**. Si dentro de una palabra aparece `0x52` (`'R'`), no es un `RUN`: es un dato.

### 3.3 Fin de la carga: `LOADING` → `READY` o `IDLE`

**Si el checksum coincide** → `READY`. Antes de responder, la DU:

- rellena con HALT la parte de la IMEM que el programa no usa,
- escribe ceros en toda la DMEM y limpia el bitmap de memoria usada,
- resetea el núcleo: PC = 0, registros en 0, latches con `valid = 0`, contador de ciclos en 0,
- responde `ACK`.

**Si algo falló** → `IDLE`, con **toda** la IMEM rellena de HALT, y responde `NACK`. Pueden fallar cuatro cosas:

| Falla          | Qué significa                                                                                            |
| -------------- | -------------------------------------------------------------------------------------------------------- |
| `ERR_CHECKSUM` | Llegaron todos los bytes, pero alguno se corrompió en el cable                                           |
| `ERR_TIMEOUT`  | Pasaron **100 ms sin que llegue ningún byte** en medio de la carga (por ejemplo, se desenchufó el cable) |
| `ERR_PARIDAD`  | Un byte llegó con el bit de paridad incorrecto                                                           |
| `ERR_TAMANO`   | `N` es 0 o mayor que 256                                                                                 |

**Sobre el timeout:** no es un tiempo total para el `LOAD`, sino el tiempo **entre un byte y el siguiente**. Cada byte que llega reinicia el contador. Un programa largo puede tardar varios segundos en cargarse sin problema, siempre que no haya un hueco de 100 ms.

**¿Por qué rellenar con HALT y no dejar lo que había?** Porque las primeras palabras ya se escribieron. La IMEM quedó con la mitad del programa nuevo y la mitad del viejo: una mezcla que no es ningún programa. Rellenarla con HALT garantiza que, si alguien la ejecuta igual, se detiene en la primera instrucción. Y como no hay programa válido, la DU vuelve a `IDLE`.

**¿Y los errores a mitad de la carga?** Paridad y tamaño se detectan **antes** de que termine de llegar la carga. Si la DU respondiera en ese momento, los bytes que siguen llegando se leerían como comandos. Por eso primero espera a que la línea quede en silencio (100 ms) y recién después responde el `NACK` ([protocolo §7.2](protocolo.md)).

### 3.4 `STEP`: `READY` → `DUMPING` → `STEPPING`

Llega `'S'`. La DU:

1. pone `i_enable = 1` durante **exactamente un ciclo de reloj**: el núcleo avanza un ciclo y todas las instrucciones del pipeline se corren una etapa;
2. vuelve a poner `i_enable = 0`, y el núcleo queda congelado;
3. pasa a `DUMPING` y envía el snapshot (la "foto" de registros, latches y memoria usada);
4. cuando sale el último byte del snapshot, pasa a `STEPPING`.

¿Por qué `STEPPING` y no `READY`? Porque `READY` significa "limpio, en el ciclo 0". Después de un paso ya no lo está: se ejecutó al menos un ciclo.

Cada `STEP` siguiente hace lo mismo: `STEPPING` → `DUMPING` → `STEPPING`.

**Excepción:** si en ese ciclo el HALT llegó a WB, la ejecución terminó, así que al salir de `DUMPING` va a `HALTED` en lugar de a `STEPPING` (ver 3.6).

### 3.5 Comandos desde `STEPPING`

| Llega   | Pasa a                 | Para qué sirve                                                                                     |
| ------- | ---------------------- | -------------------------------------------------------------------------------------------------- |
| `STEP`  | `DUMPING` → `STEPPING` | Otro paso                                                                                          |
| `RUN`   | `RUN`                  | "Ya vi lo que quería, corré hasta el final"                                                        |
| `RESET` | `READY`                | Volver a empezar el **mismo** programa desde el ciclo 0 sin reenviarlo (limpia todo menos la IMEM) |
| `LOAD`  | `LOADING`              | Abandonar esta depuración y cargar otro programa                                                   |
| `DUMP`  | `DUMPING` → `STEPPING` | Pedir la foto de nuevo sin avanzar (por ejemplo, si se perdió la anterior)                         |

> **Ojo:** `ACK` no es un comando, es una **respuesta** de la FPGA. La PC nunca manda un `ACK`. Los que llevan de `STEPPING` a `READY` son `RESET` y, pasando por `LOADING`, `LOAD`.

`RESET` y `LOAD` se aceptan en `STEPPING` porque, en modo paso a paso, el programa puede no terminar nunca (por ejemplo, un loop infinito). Sin esos dos comandos, no habría forma de salir sin apretar el botón de la placa (ADR-010).

### 3.6 `RUN`: `READY`/`STEPPING` → `RUN` → `DUMPING` → `HALTED`

Llega `'R'`. La DU responde `ACK` **enseguida** (para que la PC sepa que el comando llegó) y deja `i_enable = 1` en todos los ciclos. El núcleo corre a toda velocidad.

En `RUN` la DU **sigue escuchando la UART**, pero solo acepta `ABORT` (y `PING`). Cualquier otro comando responde `NACK(ERR_ESTADO)` y la ejecución sigue.

**¿Cuándo termina?** Hay tres motivos:

| Motivo    | Quién lo detecta y cómo                                                                                                                                                                      |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HALTED`  | El **núcleo**. Detecta el HALT en **ID** y deja de buscar instrucciones, pero el HALT sigue avanzando. Cuando llega a **WB**, todo lo anterior ya terminó: el núcleo pone `o_halted = 1`     |
| `ILLEGAL` | El **núcleo**, igual que el HALT: la instrucción ilegal se detecta en ID y avanza marcada. Al llegar a WB pone `o_halted = 1` **y** `o_illegal = 1`                                          |
| `ABORTED` | La **DU**. Llega `'A'`, pone `i_stop_fetch = 1` (no se buscan más instrucciones) y espera a que las que ya estaban adentro terminen, o sea, a que los 4 bits `valid` de los latches valgan 0 |

La DU no decodifica instrucciones: solo **mira las salidas `o_halted` y `o_illegal`** del núcleo (y los `valid` en el caso de `ABORT`).

¿Por qué esperar a WB y no detenerse en ID? Porque en ese momento todavía hay instrucciones **más viejas** en EX, MEM y WB que no terminaron. Si se cortara en ID, quedarían a medio ejecutar. Esperar a WB garantiza que el pipeline quede vacío (R-EJ-5).

**Al terminar**, por cualquiera de los tres motivos:

1. `i_enable = 0` (el núcleo queda congelado);
2. pasa a `DUMPING` y envía el snapshot final, con el motivo dentro del byte `estado`;
3. al terminar de enviar, pasa a `HALTED`.

Entonces, respondiendo a la pregunta: **`RUN` pasa a `DUMPING` solo cuando la ejecución terminó**, y eso puede ser por HALT, por instrucción ilegal **o por `ABORT`**. Mientras no termine, se queda en `RUN`.

### 3.7 `DUMPING`: cuándo sale y adónde va

Sale **cuando se envió el último byte de la trama**, es decir, el checksum. ¿Adónde? Depende de por qué entró:

| Entró por                 | Sale a                                                 |
| ------------------------- | ------------------------------------------------------ |
| `DUMP`/`DUMP_MEM` desde X | X, el mismo estado de antes (lo guarda `r_prev_state`) |
| `STEP` sin terminar       | `STEPPING`                                             |
| `STEP` que terminó        | `HALTED`                                               |
| Fin de `RUN` o `ABORT`    | `HALTED`                                               |

`r_prev_state` es un registro que se carga **al entrar** a `DUMPING`, con el estado del que viene. `DUMPING` no tiene una flecha de "volver atrás" genérica, porque una FSM en hardware necesita saber a qué estado concreto ir. Por eso el diagrama dibuja una salida por cada estado posible, con la condición `[prev = X]`.

Mientras `DUMPING` envía, cualquier byte que llega se **descarta sin respuesta**: la PC tiene que esperar a recibir la trama completa.

### 3.8 `HALTED`: el final

El programa terminó y el pipeline está vacío. Desde acá se puede:

- `DUMP` / `DUMP_MEM`: volver a mirar el estado final (vuelve a `HALTED`; el motivo se conserva);
- `RESET` → `READY`: correr de nuevo el mismo programa;
- `LOAD` → `LOADING`: cargar otro programa.

`RUN` y `STEP` responden `NACK(ERR_ESTADO)`: no hay nada más que ejecutar sin reiniciar.

## 4. ¿Por qué se llega a `LOADING` desde `HALTED`, `STEPPING`, `READY` e `IDLE`?

Porque **cargar un programa nuevo tiene sentido cada vez que el núcleo no está corriendo**:

- `IDLE`: es la primera carga.
- `HALTED`: terminó un programa y querés probar otro. Es el caso más común: la métrica del proyecto pide 5 cargas seguidas sin resintetizar.
- `READY`: cargaste el programa equivocado y lo querés cambiar antes de correrlo.
- `STEPPING`: estás depurando paso a paso, encontraste el bug, lo corregiste en la PC y querés cargar la versión nueva sin terminar la ejecución anterior.

**¿Por qué no desde `RUN`?** Porque el núcleo está leyendo la IMEM en ese mismo momento: escribirla en medio de la ejecución ejecutaría una mezcla de programas. Primero hay que mandar `ABORT` (→ `HALTED`) y después `LOAD`.

Como `LOAD` siempre limpia todo (ADR-009), no importa desde qué estado se haga: el resultado es el mismo que después de encender la placa, pero con el programa nuevo.

## 5. Lo que no está dibujado como flecha

Para no llenar el diagrama de autolazos, hay dos reglas que valen en todos los estados que aceptan comandos:

- `PING` responde la versión del protocolo y **no cambia el estado**.
- Un comando desconocido, o uno inválido para ese estado, responde `NACK` y **no cambia nada**.

El botón de reset de la placa (`i_reset`) lleva a `IDLE` desde **cualquier** estado.

## 6. Errores comunes al razonar la FSM

- **Confundir el motivo con el estado.** `HALTED`, `ILLEGAL` y `ABORTED` son motivos de terminación que viajan en el snapshot. El estado es siempre `HALTED`.
- **Creer que `STEP` = una instrucción.** Es **un ciclo de reloj**. Una instrucción tarda 5 ciclos en atravesar el pipeline, y en cada ciclo hay hasta 5 instrucciones avanzando a la vez.
- **Creer que la DU detecta el HALT.** Lo detecta el núcleo. La DU solo mira `o_halted`.
- **Pensar que el timeout es para todo el `LOAD`.** Es entre bytes.
- **Interpretar bytes de datos como comandos.** En `LOADING` todo byte es dato, aunque valga `'R'`.
