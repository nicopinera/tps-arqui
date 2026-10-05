# ADR-003 — Protocolo de comandos de la Debug Unit

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-104, Hito 4, US-410
- **Relacionados:** ADR-002 (UART y paridad), ADR-008 (memoria usada), ADR-010 (`ABORT`), ADR-017 (layout del snapshot)

## Contexto

El enunciado pide que la Debug Unit permita cargar un programa, ejecutarlo en modo continuo o paso a paso y volcar el estado, pero no define cómo se comunica con la PC (PRD §14, A5). El protocolo tiene que:

- soportar comandos sin argumentos (`STEP`, `RUN`, …) y con argumentos de tamaño variable (`LOAD`);
- devolver respuestas de tamaño variable (un `ACK` de pocos bytes o un snapshot de cientos);
- detectar errores de transmisión y no dejar nunca a la Debug Unit colgada (NFR-6);
- responder siempre algo, para que la PC sepa si el comando llegó (R-DU-2);
- ser simple de implementar en una FSM de hardware.

Este protocolo es el contrato entre la pista de hardware (`du_cmd_fsm.v`) y la de software (`protocol/codec.py`), así que se fija antes de que cada una empiece a implementar su parte.

## Decisión

### PC → FPGA: 1 byte de comando (ASCII) + argumentos binarios

| Byte         | Comando | Argumentos                                                                    | Estados válidos (R-DU-1) | Respuesta                                                 |
| ------------ | ------- | ----------------------------------------------------------------------------- | ------------------------ | --------------------------------------------------------- |
| `0x4C` ('L') | `LOAD`  | `N` (2 bytes, LE) + `N` palabras de 4 bytes (LE) + checksum (1 byte)          | `IDLE`, `READY`, `STEPPING`, `HALTED` (ADR-010) | `ACK` / `NACK(err)`                                       |
| `0x52` ('R') | `RUN`   | —                                                                             | `READY`, `STEPPING`      | `ACK` inmediato; al terminar, snapshot con estado `HALTED` |
| `0x53` ('S') | `STEP`  | —                                                                             | `READY`, `STEPPING`      | Snapshot                                                  |
| `0x44` ('D') | `DUMP`  | —                                                                             | Todos salvo `RUN`        | Snapshot                                                  |
| `0x58` ('X') | `RESET` | —                                                                             | `IDLE`, `READY`, `STEPPING`, `HALTED` (ADR-010) | `ACK`                                                     |
| `0x41` ('A') | `ABORT` | —                                                                             | `RUN`                    | Snapshot con estado `ABORTED`                             |
| `0x3F` ('?') | `PING`  | —                                                                             | Todos                    | `ACK` + versión del protocolo/hardware (1 byte)           |
| `0x4D` ('M') | `DUMP_MEM` | dirección inicial (2 bytes, LE) + cantidad de palabras (2 bytes, LE)       | Todos salvo `RUN`        | Trama con las palabras pedidas / `NACK(rango)` — agregado por ADR-008 |

- El checksum de `LOAD` es el **XOR de todos los bytes que siguen al byte de comando** (los 2 de `N` y los `4·N` de las palabras).
- Un byte de comando desconocido, o un comando inválido para el estado actual, responde `NACK` con su código de error y **no cambia nada**.

### FPGA → PC: todas las respuestas son tramas

```text
[0xA5] [tipo: 1 B] [longitud: 2 B, LE] [payload: longitud B] [checksum: 1 B]
```

- `0xA5` es el byte de sincronización.
- `tipo`: `ACK`, `NACK`, `SNAPSHOT`, `PING_INFO`. Los valores numéricos se fijan en `docs/protocolo.md` (US-104).
- `NACK` lleva 1 byte de payload con el código de error: comando inválido para el estado, comando desconocido, checksum incorrecto, tamaño excedido, timeout de recepción, error de paridad (ADR-002).
- **Checksum: XOR de 8 bits** de `tipo`, `longitud` y `payload`. Se incluye la cabecera para que una longitud corrupta también se detecte.

### Robustez

- **Timeout de recepción en hardware** (PRD R-DU-6): si un comando con argumentos se interrumpe (por ejemplo, la PC se desconecta a mitad de un `LOAD`), la Debug Unit descarta lo recibido y responde `NACK(timeout)`. Si era un `LOAD`, se trata igual que un checksum inválido: la IMEM queda rellena con HALT y vuelve a `IDLE` (ADR-009), porque parte de la IMEM ya se había sobrescrito. En cualquier otro comando vuelve al estado anterior. El tiempo exacto se fija en US-104 (propuesta: 100 ms sin bytes).
- **Timeout del lado de la PC:** si no llega respuesta en un tiempo acotado, la sesión lo informa y puede reintentar (`session/debug_session.py`).
- Un `LOAD` con checksum inválido se rechaza completo: la IMEM no queda a medio escribir (R-DU-4). Esto implica que el `du_loader` valida el checksum antes de dar el programa por cargado (ver ADR-009).

## Alternativas consideradas

**Formato de los comandos**

| Opción                                           | Ventajas                                                                                         | Desventajas                                                                                      |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| **(a) 1 byte ASCII + argumentos binarios** (elegida) | Se prueba a mano mandando una letra desde una terminal; el decodificador en hardware es un `case` | `LOAD` no se puede escribir a mano (es binario)                                                  |
| (b) Comandos de texto (`step\n`)                 | Muy legibles                                                                                     | Hay que parsear cadenas en hardware: más estados, más lógica y más lento                         |
| (c) Tramas binarias con cabecera, igual que las respuestas | Formato uniforme en ambos sentidos                                                       | No se puede probar a mano; agrega bytes a comandos que no tienen argumentos                       |

**Checksum**

| Opción                       | Ventajas                                                     | Desventajas                                                                                  |
| ---------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| **(a) XOR de 8 bits** (elegida) | Un registro y un XOR en hardware; una línea en Python        | No detecta bytes reordenados ni dos errores en el mismo bit de bytes distintos               |
| (b) Suma módulo 256          | Igual de barata, algo mejor ante errores múltiples            | Ganancia marginal frente al XOR                                                              |
| (c) CRC-8                    | La detección más robusta                                     | LFSR en hardware y tabla en Python; es más de lo que hace falta en un cable USB de 1 m      |

El XOR alcanza porque no es la única protección: la paridad (ADR-002) ya detecta los errores de 1 bit por byte, y el timeout detecta los bytes perdidos.

**Respuesta de `RUN`**

| Opción                                      | Ventajas                                                                       | Desventajas                                                                                    |
| ------------------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| **(a) `ACK` + snapshot al terminar** (elegida) | La PC sabe enseguida que el comando llegó; cumple R-DU-2                       | Dos respuestas para un mismo comando; la PC tiene que esperar la segunda sin timeout corto     |
| (b) Solo el snapshot al terminar            | Una sola respuesta                                                             | Con un loop infinito la PC no distingue "corriendo" de "comando perdido"                        |

## Consecuencias

**Positivas**

- Cualquier comando sin argumentos se prueba desde una terminal serie mandando un solo carácter.
- El byte de sincronización y la longitud permiten que la PC se resincronice después de un error.
- Una carga corrupta nunca se ejecuta.
- La FSM del hardware queda chica: un estado para el comando, unos pocos para recibir los argumentos de `LOAD`, y un serializador genérico de tramas para todas las respuestas.

**Negativas**

- `protocol/comandos.py` y `du_defs.vh` tienen que estar sincronizados. Se mitiga generando el `.vh` desde Python o, como mínimo, con un test que compare los dos archivos (PRD §13).
- Durante `RUN`, el único comando que se acepta es `ABORT`; cualquier otro responde `NACK`.

**Restricciones que impone**

- `docs/protocolo.md` (US-104) fija los valores de `tipo`, los códigos de error, el timeout y ejemplos byte a byte de cada comando.
- Toda respuesta pasa por un único serializador de tramas en hardware (`du_dumper` / transmisor de tramas), que calcula el checksum al vuelo.
- El layout del payload `SNAPSHOT` lo define ADR-017.

## Referencias

- PRD §3.1 (comandos y snapshot), §6 (R-DU-1 a R-DU-6), §7 (NFR-6), §8 (ADR-003), §14 (A5); US-104, US-402, US-409, US-410.
