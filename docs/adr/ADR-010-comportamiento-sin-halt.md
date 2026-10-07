# ADR-010 — Comportamiento sin instrucción de parada

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-406
- **Relacionados:** ADR-003 (`ABORT`), ADR-004 (codificación de HALT), ADR-008 (tamaño de IMEM), ADR-009 (relleno con HALT), ADR-013 (ensamblador)

## Contexto

El enunciado pregunta qué pasa si un programa no tiene instrucción de parada. Sin ninguna protección:

1. El PC sigue incrementándose después de la última instrucción del programa.
2. Al pasar `0x3FC` (fin de la IMEM de 256 palabras, ADR-008), los bits altos de la dirección se ignoran y el PC "da la vuelta" a `0x000`.
3. El procesador ejecuta en loop lo que haya en memoria: el mismo programa otra vez, restos de un programa anterior, o ceros. (`0x00000000` es una instrucción ilegal en RV32I; con la decisión de ADR-018, este diseño detiene la ejecución con estado `ILLEGAL` al encontrarla, pero un programa viejo que siga en memoria se ejecutaría igual.)
4. En modo continuo, la ejecución **nunca termina**: la Debug Unit nunca llega a `HALTED` ni envía el snapshot final, y la PC queda esperando.

Hay dos casos distintos que hay que cubrir:

- **Programa que "se cae" del final** porque le falta el HALT.
- **Loop infinito** dentro del programa (por ejemplo, `loop: j loop`): ningún relleno de memoria lo detiene, porque el PC nunca llega a la zona rellena.

## Decisión

Se combinan tres mecanismos:

| #   | Mecanismo                                     | Dónde                | Qué caso cubre                                                                     |
| --- | --------------------------------------------- | -------------------- | ---------------------------------------------------------------------------------- |
| (a) | **Relleno de la IMEM con HALT** en cada carga | Hardware (ADR-009)   | Programa sin HALT cargado con otra herramienta o con `.word`: termina igual al llegar al relleno |
| (b) | **HALT automático del ensamblador**           | Software (R-PR-1)    | Programa escrito sin HALT: el ensamblador agrega uno al final y emite una advertencia |
| (c) | **Comando `ABORT`**                           | Debug Unit (ADR-003) | Loop infinito en modo `RUN`: el usuario corta la ejecución desde la PC              |

**Semántica de `ABORT`** (solo válido en `RUN`):

1. La Debug Unit le indica al núcleo que deje de buscar instrucciones: el PC se congela y a IF/ID entran burbujas, igual que cuando se detecta un HALT (R-EJ-3). La instrucción que estaba en IF/ID se descarta.
2. El núcleo sigue habilitado hasta que las instrucciones que ya estaban en ID/EX, EX/MEM y MEM/WB completan WB (como máximo 3 ciclos) y los 4 latches quedan con `valid = 0`.
3. Se congela el núcleo (`i_enable = 0`) y se envía un snapshot con estado `ABORTED`.
4. La Debug Unit pasa a `HALTED`: se puede hacer `DUMP`, `DUMP_MEM`, `RESET` o `LOAD`.

En modo paso a paso no hace falta `ABORT`: el usuario deja de mandar `STEP` y puede hacer `RESET` o `LOAD` desde `STEPPING`. Esto implica que `RESET` y `LOAD` también son válidos en `STEPPING` (se actualiza R-DU-1 en `docs/protocolo.md`).

## Alternativas consideradas

| Opción                                    | Cubre "sin HALT" | Cubre loop infinito | Costo                                                   | ¿Se adopta?                                                       |
| ----------------------------------------- | ---------------- | ------------------- | ------------------------------------------------------- | ----------------------------------------------------------------- |
| (a) Relleno con HALT                      | Sí               | No                  | Ya incluido en ADR-009                                  | **Sí**                                                            |
| (b) HALT automático del ensamblador       | Sí               | No                  | Unas líneas en el ensamblador                           | **Sí**                                                            |
| (c) Comando `ABORT`                       | Sí               | Sí (manual)         | Un comando más en la FSM de `RUN`                       | **Sí**                                                            |
| (d) Watchdog de ciclos (estado `TIMEOUT`) | Sí               | Sí (automático)     | Contador de 32 bits + comando/parámetro para configurarlo | No: `ABORT` ya cubre el caso; queda en el roadmap                 |
| (e) Detener si el PC sale del rango cargado | Sí             | No                  | Registro con la última dirección + comparador           | No: (a) produce el mismo efecto sin hardware extra                |
| Solo (b) + botón de reset de la placa     | Parcial          | Sí (reset físico)   | Ninguno                                                 | No: un loop infinito deja la Debug Unit colgada e incumple NFR-6  |

## Consecuencias

**Positivas**

- Ningún programa puede dejar la Debug Unit colgada: o termina en un HALT (propio, agregado o de relleno) o se corta con `ABORT`. Cumple NFR-6.
- Respuesta clara para el informe, con demostración en placa usando los programas de `asm/special/` (`no_halt.asm` e `infinite_loop.asm`).
- `ABORT` reutiliza el mecanismo de drenado del HALT: no hay una segunda forma de vaciar el pipeline.
- El pipeline queda vacío también al abortar, en línea con la interpretación de "terminar" de PRD §14, A11.

**Negativas**

- Un loop infinito no termina solo: hace falta que el usuario mande `ABORT`. La GUI y la CLI tienen que ofrecerlo de forma visible mientras dura `RUN`.
- El HALT agregado por el ensamblador ocupa una palabra de la IMEM, que cuenta para el límite de ADR-008.
- Si por algún motivo una zona de la IMEM no estuviera rellenada (por ejemplo, después del encendido sin `LOAD`), un programa que se "cae" del final encontraría ceros y terminaría con estado `ILLEGAL` (ADR-018) en lugar de `HALTED`.

**Restricciones que impone**

- El núcleo expone una entrada para detener la búsqueda (`i_stop_fetch` o equivalente) que reutiliza la lógica del HALT; se define en `docs/interfaces/riscv_core.md` (US-103).
- Mientras está en `RUN`, la Debug Unit sigue escuchando la UART y acepta `ABORT`; cualquier otro comando responde `NACK`.
- La PC no usa timeout corto mientras espera el snapshot final de `RUN` (ADR-003).

## Referencias

- PRD §6 (R-EJ-3, R-EJ-5, R-PR-1, R-DU-1), §7 (NFR-6), §8 (ADR-010), §14 (A11); US-406.
