# ADR-001 — Control de ejecución por clock enable

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** Hito 2
- **Relacionados:** ADR-005 (enable del puerto de BRAM), ADR-007 (bypass interno en vez de escritura en flanco de bajada), ADR-016 (frecuencia y MMCM)

## Contexto

El enunciado pide dos cosas que parecen contradecirse:

1. Un **modo paso a paso** en el que "enviando un comando se ejecuta un ciclo de clock".
2. Que "el clock no debe verse intervenido en ninguna parte del proyecto".

No se contradicen si "ejecutar un ciclo" se entiende como "**avanzar el procesador** un ciclo", no como "generar un flanco de reloj". El reloj puede correr siempre. Lo que se habilita durante un ciclo es la actualización del estado del núcleo.

Además, la Debug Unit y la UART tienen que seguir funcionando mientras el procesador está detenido: reciben comandos, leen registros y memoria, y transmiten el snapshot.

## Decisión

- El núcleo (`riscv_core`) recibe una señal `i_enable` que actúa como **clock enable** de todos sus elementos de estado:
  - PC,
  - latches IF/ID, ID/EX, EX/MEM y MEM/WB,
  - banco de registros (puerto de escritura),
  - puertos de escritura de IMEM y DMEM del lado del núcleo,
  - puertos de lectura sincrónica de BRAM del lado del núcleo.
- Si `i_enable = 0`, ninguno de esos elementos cambia aunque llegue el flanco de reloj.
- La Debug Unit genera `i_enable`:
  - **STEP:** un pulso de exactamente 1 ciclo de reloj (R-EJ-2).
  - **RUN:** nivel sostenido en 1 hasta que se detecta el fin de la ejecución (R-EJ-5) o llega un `ABORT`.
- El reloj llega a **todos** los flip-flops por la red global (BUFG, o MMCM), sin pasar por ninguna compuerta, divisor ni buffer con enable.
- La UART y la Debug Unit **siempre** están habilitadas.

## Consecuencias

**Positivas:**

- Un único dominio de reloj para todo el diseño: el análisis de timing (WNS/WHS, skew) es directo.
- La Debug Unit y la UART funcionan mientras el núcleo está congelado, así que se puede volcar el estado en cualquier ciclo.
- STEP y RUN usan el mismo mecanismo, lo que facilita cumplir R-EJ-7 (mismo resultado en ambos modos).
- Cumple NFR-2: no hay lógica en la red de reloj, y se puede verificar con `report_clock_networks`.

**Negativas:**

- `i_enable` llega a cientos de flip-flops (fan-out alto) y puede aparecer en el camino crítico. Se mide en US-601; si hace falta, se registra o se replica (Vivado `MAX_FANOUT`).
- Cada elemento de estado del núcleo tiene que respetar `i_enable` explícitamente. Si se olvida en uno solo (por ejemplo, el enable del puerto de lectura de la BRAM), un stall o un paso cambia estado que no debía cambiar.

**Restricciones que impone:**

- Prohibida cualquier expresión que involucre `clock` fuera de `@(posedge clock)`.
- Prohibido escribir el banco de registros en el flanco de bajada: se resuelve con bypass interno (ADR-007).
- Los testbenches del núcleo tienen que probar que, con `i_enable = 0`, ningún elemento de estado cambia durante N ciclos.
