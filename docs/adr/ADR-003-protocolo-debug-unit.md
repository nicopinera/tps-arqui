# ADR-003 — Protocolo de comandos de la Debug Unit

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-104, Hito 4, US-410
- **Relacionados:** ADR-002 (UART y paridad), ADR-008 (memoria usada), ADR-010 (`ABORT`), ADR-017 (layout del snapshot)

## Contexto

El enunciado pide que la Debug Unit permita cargar un programa, ejecutarlo en modo continuo o paso a paso y volcar el estado, pero no define cómo se comunica con la PC. El protocolo tiene que:

- soportar comandos sin argumentos (`STEP`, `RUN`, …) y con argumentos de tamaño variable (`LOAD`);
- devolver respuestas de tamaño variable (un `ACK` de pocos bytes o un snapshot de cientos);
- detectar errores de transmisión y no dejar nunca a la Debug Unit colgada;
- responder siempre algo, para que la PC sepa si el comando llegó;
- ser simple de implementar en una FSM de hardware.

Este protocolo es el contrato entre la pista de hardware (`du_cmd_fsm.v`) y la de software (`protocol/codec.py`), así que se fija antes de que cada una empiece a implementar su parte.

## Decisión

### PC → FPGA: 1 byte de comando (ASCII) + argumentos binarios

| Byte         | Comando    | Argumentos                                                           | Estados válidos (R-DU-1)                        | Respuesta                                                             |
| ------------ | ---------- | -------------------------------------------------------------------- | ----------------------------------------------- | --------------------------------------------------------------------- |
| `0x4C` ('L') | `LOAD`     | `N` (2 bytes, LE) + `N` palabras de 4 bytes (LE) + checksum (1 byte) | `IDLE`, `READY`, `STEPPING`, `HALTED` (ADR-010) | `ACK` / `NACK(err)`                                                   |
| `0x52` ('R') | `RUN`      | —                                                                    | `READY`, `STEPPING`                             | `ACK` inmediato; al terminar, snapshot con estado `HALTED`            |
| `0x53` ('S') | `STEP`     | —                                                                    | `READY`, `STEPPING`                             | Snapshot                                                              |
| `0x44` ('D') | `DUMP`     | —                                                                    | Todos salvo `RUN`                               | Snapshot                                                              |
| `0x58` ('X') | `RESET`    | —                                                                    | `IDLE`, `READY`, `STEPPING`, `HALTED` (ADR-010) | `ACK`                                                                 |
| `0x41` ('A') | `ABORT`    | —                                                                    | `RUN`                                           | Snapshot con estado `ABORTED`                                         |
| `0x3F` ('?') | `PING`     | —                                                                    | Todos                                           | `ACK` + versión del protocolo/hardware (1 byte)                       |
| `0x4D` ('M') | `DUMP_MEM` | dirección inicial (2 bytes, LE) + cantidad de palabras (2 bytes, LE) | Todos salvo `RUN`                               | Trama con las palabras pedidas / `NACK(rango)` — agregado por ADR-008 |

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

## Consecuencias

**Positivas:**

- Cualquier comando sin argumentos se prueba desde una terminal serie mandando un solo carácter.
- El byte de sincronización y la longitud permiten que la PC se resincronice después de un error.
- Una carga corrupta nunca se ejecuta.
- La FSM del hardware queda chica: un estado para el comando, unos pocos para recibir los argumentos de `LOAD`, y un serializador genérico de tramas para todas las respuestas.

**Negativas:**

- `protocol/comandos.py` y `du_defs.vh` tienen que estar sincronizados. Se mitiga generando el `.vh` desde Python o, como mínimo, con un test que compare los dos archivos (PRD §13).
- Durante `RUN`, el único comando que se acepta es `ABORT`; cualquier otro responde `NACK`.

**Restricciones que impone:**

- `docs/protocolo.md` (US-104) fija los valores de `tipo`, los códigos de error, el timeout y ejemplos byte a byte de cada comando.
- Toda respuesta pasa por un único serializador de tramas en hardware (`du_dumper` / transmisor de tramas), que calcula el checksum al vuelo.
- El layout del payload `SNAPSHOT` lo define ADR-017.
