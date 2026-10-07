# ADR-008 — Tamaños de memoria y definición de "memoria usada"

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-204, US-405, US-409
- **Relacionados:** ADR-002 (velocidad del enlace), ADR-003 (protocolo), ADR-005 (memoria distribuida), ADR-009 (limpieza en cada carga), ADR-017 (layout del snapshot)

## Contexto

El enunciado pide enviar a la PC "la memoria de datos usada", pero no define qué significa "usada" (PRD §14, A3) ni fija el tamaño de las memorias (A7).

- El tamaño determina cuántos LUTs ocupan las memorias (ADR-005, memoria distribuida) y el límite de programa que acepta el ensamblador (R-PR-2).
- La definición de "usada" determina cuántos bytes viajan en cada snapshot. A 19200 bps (ADR-002) cada palabra de memoria con su dirección (6 B, ADR-017) cuesta ~3,4 ms, así que mandar la DMEM completa en cada paso agrega cerca de 1 s.

## Decisión

### Tamaños

- **IMEM: 256 palabras (1 KiB). DMEM: 256 palabras (1 KiB).**
- Son parámetros (`IMEM_DEPTH`, `DMEM_DEPTH` y sus `ADDR_BITS`); estos son los valores por defecto. El software de PC los obtiene de `docs/protocolo.md` / `comandos.py` (y opcionalmente del `PING`).
- Direcciones válidas: IMEM `0x000`–`0x3FC`, DMEM `0x000`–`0x3FF`. Fuera de rango, los bits altos de la dirección se ignoran (la memoria "da la vuelta").

### "Memoria usada" = palabras escritas por el programa desde la última carga

- **Bitmap de escritura:** un registro de `DMEM_DEPTH` bits (256 flip-flops). Cuando un store del núcleo escribe una palabra (`sw`, `sh` o `sb`, con `valid` e `i_enable`), se pone en 1 el bit de esa palabra.
- **Contador de palabras usadas:** se incrementa cada vez que un bit del bitmap pasa de 0 a 1. Hace falta porque la trama de respuesta lleva la longitud **antes** del payload (ADR-003).
- El bitmap y el contador se limpian en `LOAD` y `RESET` (ADR-009). Las escrituras de limpieza que hace la Debug Unit **no** marcan el bitmap.
- **En el snapshot** se envían solo las palabras marcadas, cada una como `[dirección][dato]` (ADR-017), en orden de dirección creciente.
- **Comando auxiliar `DUMP_MEM`** para ver datos que el programa lee pero no escribe:

  | Byte         | Comando    | Argumentos                                         | Estados válidos   | Respuesta                                    |
  | ------------ | ---------- | -------------------------------------------------- | ----------------- | -------------------------------------------- |
  | `0x4D` ('M') | `DUMP_MEM` | dirección inicial (2 B, LE) + cantidad de palabras (2 B, LE) | Todos salvo `RUN` | Trama con las palabras pedidas, o `NACK(rango)` |

  Se agrega a la tabla de comandos de ADR-003.

## Alternativas consideradas

**Tamaños**

| Opción                                       | Ventajas                                                     | Desventajas                                                               |
| -------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------- |
| **(a) 256 + 256 palabras** (elegida)         | Alcanza de sobra para pruebas y demos; costo bajo en LUTs    | —                                                                         |
| (b) IMEM 512, DMEM 256                       | Más lugar para demos largas                                  | El doble de LUTs en la IMEM sin una necesidad concreta                    |
| (c) 128 + 128 palabras                       | Mínimo de LUTs                                               | Queda justo para las demos y no deja margen para el relleno de HALT       |

**Definición de "usada"**

| Opción                                                 | Ventajas                                                                             | Desventajas                                                                                         |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| **(a) Bitmap de escritas + `DUMP_MEM`** (elegida)      | Responde literalmente a "usada"; minimiza bytes; `DUMP_MEM` cubre los datos que solo se leen | 256 FFs + contador; un comando más en la FSM                                                         |
| (b) Solo bitmap de escritas                            | Sin comandos nuevos                                                                  | No hay forma de ver la memoria que el programa lee y no escribe                                     |
| (c) Rango `[0, máx. escrita]`                          | Un solo registro                                                                     | Una escritura en una dirección alta arrastra todo el rango                                          |
| (d) Toda la DMEM siempre                               | Lo más simple                                                                        | ~1,5 KiB extra por snapshot: ~0,9 s más por paso a 19200 bps; deja NFR-4 en el límite siempre         |

## Consecuencias

**Positivas**

- El snapshot típico solo agrega unas pocas palabras: un programa de prueba escribe del orden de 1 a 20 palabras (3 a 70 ms extra a 19200 bps).
- La definición es precisa y fácil de explicar en el informe: "usada = escrita por el programa desde la última carga".
- `DUMP_MEM` permite inspeccionar cualquier zona de memoria sin cambiar el snapshot.

**Negativas**

- Un programa que escribe toda la DMEM genera un snapshot de ~1,7 KiB (~1 s a 19200 bps), que queda en el límite de NFR-4 en ese caso extremo (ver ADR-002).
- La lectura (`lw`/`lh`/`lb`) no marca nada: si un programa lee una palabra sin escribirla, no aparece en el snapshot. Se cubre con `DUMP_MEM`.
- El dumper tiene que recorrer el bitmap (256 ciclos como máximo, despreciable frente a la UART).

**Restricciones que impone**

- El ensamblador rechaza programas de más de 256 palabras, contando el HALT final (R-PR-2).
- El bitmap se actualiza con la misma condición que la escritura de DMEM: `mem_write && valid && i_enable` (R-EJ-6).
- `docs/protocolo.md` incluye `DUMP_MEM` y el código de error de rango inválido.

## Referencias

- PRD §3.5 (presupuesto de volcado), §6 (R-PR-2), §7 (NFR-3, NFR-4), §8 (ADR-008), §14 (A3, A7); US-204, US-405, US-409.
