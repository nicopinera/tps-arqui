# ADR-018 — Accesos desalineados, endianness e instrucciones ilegales

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-203, US-204, US-210
- **Relacionados:** ADR-004 (HALT y su drenado), ADR-006 (flush), ADR-010 (programa sin HALT), ADR-014 (golden model), ADR-017 (flags del snapshot)

## Contexto

El enunciado no dice qué tiene que pasar con los accesos a memoria desalineados ni con las instrucciones que no se reconocen (PRD §14, A9), y tampoco menciona el orden de bytes (A10). Los tres temas impactan en MEM, en el decodificador y en el golden model, que tienen que comportarse igual (ADR-014).

- **Endianness:** la especificación RISC-V define la memoria como little-endian.
- **Desalineados:** la especificación permite que el hardware no los soporte (puede emularlos por software o generar una excepción). Este procesador no tiene excepciones ni sistema operativo.
- **Ilegales:** sin excepciones, hay que decidir qué hace el pipeline cuando ID decodifica un opcode que no corresponde a ninguna de las 33 instrucciones.

## Decisión

### Endianness: little-endian

- El byte menos significativo de una palabra está en la dirección más baja.
- Aplica a `lb`/`lh`/`lbu`/`lhu`/`sb`/`sh` (selección de byte/media palabra con `addr[1:0]`), al envío de palabras por UART (ADR-003) y al snapshot (ADR-017).

### Accesos desalineados: se ignoran los bits bajos

- `lw`/`sw`: se ignoran `addr[1:0]` y se accede a la palabra alineada.
- `lh`/`lhu`/`sh`: se ignora `addr[0]` y se accede a la media palabra alineada.
- `lb`/`lbu`/`sb`: siempre alineados.
- No se genera ningún error en hardware. El golden model replica exactamente este comportamiento y emite una **advertencia** cuando lo detecta; el ensamblador avisa si puede detectarlo estáticamente (por ejemplo, un offset impar con base `x0`).

### Instrucciones ilegales: se detiene la ejecución con estado de error

- Una instrucción es ilegal si su opcode no es ninguno de los de PRD §2.2 (incluido HALT), o si la combinación `funct3`/`funct7` no corresponde a ninguna instrucción implementada. La lista exacta de combinaciones válidas se fija en la tabla de control de US-103.
- **Se trata como un HALT con causa de error:**
  1. Se detecta en ID. A partir de ese ciclo, IF deja de buscar (igual que R-EJ-3).
  2. La instrucción avanza por el pipeline marcada con `halt = 1` e `illegal = 1`, sin escribir registros ni memoria.
  3. Si una instrucción más vieja produce un flush (salto tomado), la ilegal se descarta como cualquier instrucción especulativa (igual que R-EJ-4): **una palabra ilegal que se buscó especulativamente no detiene nada**.
  4. Cuando llega a WB, el pipeline queda vacío y la Debug Unit pasa a `HALTED`, enviando (en `RUN`) el snapshot final con estado **`ILLEGAL`** en lugar de `HALTED`.
- El PC de la instrucción ilegal queda visible en el snapshot (en el latch MEM/WB, a través de `instr` y del estado).
- Los latches suman un bit `illegal` a los flags de ID/EX, EX/MEM y MEM/WB (ADR-017).
- El golden model se comporta igual: `run()` termina con estado `ILLEGAL` y el PC de la instrucción.

## Alternativas consideradas

**Accesos desalineados**

| Opción                                    | Ventajas                                                               | Desventajas                                                                                    |
| ----------------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **(a) Ignorar los bits bajos** (elegida)  | Cero lógica extra; permitido por la especificación                     | Un acceso desalineado lee o escribe "otra" dirección sin aviso del hardware                    |
| (b) Detener con estado `MISALIGNED`       | Más parecido a una excepción real; error visible                       | Detección en MEM, después de que instrucciones más jóvenes ya avanzaron: el drenado es más complejo que en ID |
| (c) Soportarlos (dos accesos)             | Comportamiento "como en una PC"                                        | Dos ciclos o dos puertos por acceso; complica mucho MEM y la memoria distribuida              |

**Instrucciones ilegales**

| Opción                                           | Ventajas                                                                                         | Desventajas                                                                       |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| (a) Tratarlas como NOP                           | Lo más simple                                                                                    | El programa sigue con un resultado silenciosamente incorrecto; difícil de depurar |
| **(b) Detener como HALT con error** (elegida)    | El error es visible y se sabe en qué instrucción ocurrió; reutiliza todo el mecanismo de drenado del HALT | Un estado más en la Debug Unit y en el protocolo; un bit más por latch             |
| (c) NOP + flag `illegal` en el snapshot          | Visible sin detener                                                                              | En `RUN` el flag se pierde si no se toma un snapshot en ese ciclo                  |

## Consecuencias

**Positivas**

- Los errores de codificación o de ejecución (por ejemplo, saltar a una zona de datos) se detectan en lugar de producir resultados silenciosamente incorrectos.
- `0x00000000` es ilegal en RV32I, así que ejecutar memoria en cero ahora **detiene** el procesador con estado `ILLEGAL`. Es una segunda red de seguridad para ADR-010, sumada al relleno con HALT.
- No se agrega un mecanismo nuevo de vaciado del pipeline: es el mismo camino del HALT, con una causa distinta.
- Endianness y desalineados quedan documentados y son idénticos en hardware, golden model y ensamblador.

**Negativas**

- Los accesos desalineados no se detectan en hardware: un bug de dirección en un programa produce un resultado incorrecto sin aviso (lo detecta el golden model en la verificación cruzada).
- El decodificador tiene que validar `funct3`/`funct7`, no solo el opcode: más lógica en ID.
- Se agregan el estado `ILLEGAL` (protocolo, ADR-003) y el bit `illegal` (latches, ADR-017).

**Restricciones que impone**

- `docs/protocolo.md` agrega el estado `ILLEGAL` a la lista de estados del snapshot.
- La tabla de control de US-103 marca qué combinaciones son legales.
- Casos de prueba: `lw`/`lh` desalineados (resultado igual al alineado), instrucción ilegal en el camino principal (detiene con `ILLEGAL`) e instrucción ilegal detrás de un salto tomado (no detiene).
- En el informe se documentan ambos comportamientos como decisiones de diseño y limitaciones.

## Referencias

- PRD §2.2 (observaciones: little-endian), §6 (R-EJ-3, R-EJ-4, R-EJ-4bis), §8 (ADR-018), §14 (A9, A10); US-203, US-204, US-210, US-107.
- _The RISC-V Instruction Set Manual, Volume I_: modelo de memoria little-endian, accesos desalineados y codificación ilegal `0x00000000`.
