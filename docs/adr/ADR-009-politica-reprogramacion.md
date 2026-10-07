# ADR-009 — Política de reprogramación

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-403
- **Relacionados:** ADR-003 (`LOAD`, `RESET`, checksum), ADR-004 (HALT), ADR-005 (memoria distribuida), ADR-008 (bitmap), ADR-010 (programa sin HALT)

## Contexto

El enunciado pide poder cargar programas nuevos sin resintetizar y pregunta explícitamente qué hay que limpiar al reprogramar:

- a. ¿Vaciar la memoria de datos?
- b. ¿Vaciar los registros?
- c. ¿Vaciar el pipeline?
- d. ¿Vaciar la memoria de programa?

Hay que distinguir lo que es **necesario para la corrección** de lo que es **necesario para la observabilidad y la reproducibilidad**: un programa correcto no depende de los valores previos de registros o memoria, pero el volcado sí, y la comparación contra el golden model (ADR-014) asume que todo arranca en cero.

## Decisión

### Respuesta a las preguntas del enunciado

| Pregunta                            | ¿Hace falta para la corrección?                                                                                         | Decisión                                                                                                   |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| a. ¿Vaciar la memoria de datos?     | No: un programa correcto no lee lo que no escribió. Sí para la **observabilidad**: el volcado tiene que ser reproducible | Se escriben ceros en toda la DMEM (256 ciclos ≈ 2,6 µs) y se limpian el bitmap y el contador de ADR-008     |
| b. ¿Vaciar los registros?           | No, por el mismo motivo. Sí para la **reproducibilidad** y para comparar contra el golden model, que arranca en cero     | Los 32 registros vuelven a 0                                                                               |
| c. ¿Vaciar el pipeline?             | **Sí, obligatorio**: las instrucciones del programa anterior que quedaran en los latches se completarían con el nuevo   | Flush de los 4 latches (`valid = 0`) y PC = 0                                                              |
| d. ¿Vaciar la memoria de programa?  | Depende de ADR-010: si el programa nuevo es más corto, las instrucciones viejas siguen ahí después de su final           | Las posiciones de la IMEM que no ocupa el programa nuevo se rellenan con HALT (`0x0000000B`, ADR-004)       |

### `LOAD` = reset completo + IMEM nueva

Secuencia en el `du_loader` / `du_exec_ctrl` (estado `LOADING`):

1. Se reciben las `N` palabras y se escriben en IMEM `[0, N-1]` a medida que llegan.
2. Se verifica el checksum (ADR-003).
   - **Si es inválido:** se rellena **toda** la IMEM con HALT, se responde `NACK(checksum)` y se vuelve a `IDLE`. No queda ningún programa ejecutable a medio cargar (R-DU-4).
3. Si es válido:
   - se rellena con HALT la IMEM `[N, IMEM_DEPTH-1]`,
   - en paralelo se escribe 0 en toda la DMEM y se limpian el bitmap y el contador,
   - se resetea el núcleo: latches con `valid = 0`, PC = 0, banco de registros en 0, contador de ciclos en 0.
4. Se responde `ACK` y se pasa a `READY`.

### `RESET` = lo mismo que `LOAD`, sin tocar la IMEM

- Limpia núcleo, DMEM, bitmap y contador; la IMEM conserva el programa cargado.
- Se pasa a `READY`, de modo que el mismo programa se puede volver a correr sin reenviarlo.
- Si no hay programa cargado (después del encendido), queda en `IDLE`.

## Alternativas consideradas

| Opción                                                   | Ventajas                                                                                          | Desventajas                                                                                                  |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **(a) Todo + IMEM rellena con HALT** (elegida)           | Dos ejecuciones del mismo programa dan exactamente el mismo volcado; coincide con el golden model; un programa más corto no ejecuta restos del anterior | Hay que recorrer IMEM y DMEM (≈ 2,6 µs cada una, despreciable frente a la UART)                              |
| (b) Pipeline + registros + bitmap, sin limpiar DMEM      | Un poco menos de lógica                                                                           | Un load de una dirección no escrita lee basura del programa anterior; el resultado depende del historial     |
| (c) Solo pipeline + PC (mínimo obligatorio)              | Lo mínimo para que sea correcto                                                                   | Registros y memoria arrastran valores; los volcados no son comparables entre corridas                        |

**`RESET`**

| Opción                                           | Ventajas                                                   | Desventajas                                                         |
| ------------------------------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------- |
| **(a) Igual que `LOAD` sin tocar IMEM** (elegida) | Permite volver a correr el programa sin reenviarlo; una sola rutina de limpieza | —                                                                   |
| (b) Solo el núcleo                               | Conserva la DMEM para inspeccionarla                       | Dos nociones distintas de "limpio"; la segunda corrida no es reproducible |

## Consecuencias

**Positivas**

- Se cumple R-RP-1: después de `LOAD`, el sistema queda igual que después de un reset, salvo por la IMEM.
- Cumple la métrica de reprogramación (≥ 5 cargas seguidas correctas) sin depender del orden de los programas.
- El relleno con HALT resuelve, junto con ADR-010, el caso del programa sin HALT.
- `LOAD` y `RESET` comparten la misma rutina de limpieza en hardware.

**Negativas**

- Después de un checksum inválido se pierde el programa que estaba cargado antes (la IMEM queda llena de HALT). La PC tiene que reenviar la carga.
- La memoria distribuida (ADR-005) no se limpia en un ciclo: la limpieza es un recorrido secuencial y requiere el puerto de escritura de la Debug Unit en la DMEM.

**Restricciones que impone**

- El `du_loader` necesita un contador de direcciones que recorra IMEM y DMEM, y acceso al puerto de escritura de ambas.
- El banco de registros necesita un reset sincrónico que ponga los 32 registros en 0 (o un recorrido, si se implementa en memoria distribuida).
- La IMEM y la DMEM solo se escriben desde la Debug Unit en los estados `IDLE`, `LOADING` y `HALTED` (PRD §3.3).

## Referencias

- PRD §3.3 (reglas de integridad), §6 (R-RP-1, R-DU-4, R-DU-6), §8 (ADR-009); US-403.
