# ADR-004 — Codificación de HALT

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-105, US-203
- **Relacionados:** ADR-009 (relleno de la IMEM con HALT), ADR-010 (programa sin HALT), ADR-013 (ensamblador), ADR-018 (instrucciones ilegales)

## Contexto

El enunciado exige "contar con una instrucción HALT o de stop", pero esa instrucción **no existe en RV32I** y no se da ninguna codificación (PRD §14, A2). La codificación que se elija afecta a:

- el decodificador (`control_unit.v`), que tiene que reconocerla en ID (R-EJ-3);
- el ensamblador, el desensamblador y el golden model, que la comparten desde la tabla ISA (US-105);
- la respuesta a "¿qué pasa si el programa no tiene HALT?" (ADR-010), porque algunas codificaciones hacen que la memoria vacía se detenga sola.

## Decisión

- **HALT usa el opcode _custom-0_ (`0001011`).** La palabra canónica que emite el ensamblador es **`0x0000000B`** (todos los demás campos en cero).
- **Se detecta por opcode:** toda palabra con `instr[6:0] == 7'b0001011` se decodifica como HALT, sin mirar el resto de los bits.
- En ensamblador se escribe `halt`, sin operandos. El desensamblador muestra `halt` para cualquier palabra con ese opcode.
- La semántica es la de R-EJ-3 a R-EJ-5: se detecta en ID, IF deja de buscar, el HALT avanza marcado (`halt = 1` en los latches) y la ejecución termina cuando llega a WB. No escribe registros ni memoria.

## Alternativas consideradas

| Opción                                     | Ventajas                                                                                                | Desventajas                                                                                                                          |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| (a) `0x00000000`                           | La especificación la define como ilegal a propósito; una IMEM en cero se detiene sola                    | Esconde el problema de "programa sin HALT", que el enunciado quiere que se analice; una DMEM o IMEM sin inicializar "parece" correcta |
| (b) `0xFFFFFFFF`                           | También es ilegal en RV32I                                                                               | Mismo razonamiento que (a), sin la ventaja de la memoria en cero                                                                     |
| (c) Reusar `ecall` (`0x00000073`)          | Semántica parecida: devolver el control al entorno                                                       | `ecall` es parte de RV32I con otro significado; un programa real que la use se comportaría distinto                                  |
| **(d) _custom-0_ `0x0000000B`** (elegida)  | RISC-V reserva ese espacio para extensiones propias; no choca con ninguna instrucción estándar           | Las herramientas estándar (GNU `as`, RARS) no la conocen: hay que escribirla como `.word 0x0000000B`                                  |

Se elige (d) porque es la opción correcta según la especificación: es exactamente para lo que existe el espacio _custom_. Además mantiene separados "terminar el programa" y "ejecutar memoria vacía", que es lo que pide analizar ADR-010.

**Detección por opcode vs. palabra exacta.** Comparar solo los 7 bits del opcode es más barato que comparar los 32 bits y alcanza, porque el proyecto no define otras instrucciones _custom-0_. Si en el futuro se agregara otra, habría que pasar a comparar también `funct3` o la palabra completa.

## Consecuencias

**Positivas**

- No hay conflicto con ninguna instrucción de RV32I, ni con las 32 del enunciado ni con las que no se implementan.
- Es fácil de defender en el informe: se cita la sección de la especificación que reserva _custom-0_.
- El comparador del decodificador es de 7 bits, igual que para el resto de los opcodes.

**Negativas**

- `0x00000000` no es HALT: ejecutar memoria en cero termina con estado `ILLEGAL` (ADR-018), no con `HALTED`. La terminación normal de un programa sin HALT depende del relleno de ADR-009 / ADR-010.
- El test contra el toolchain GNU (ADR-013, US-106 AC2) cubre solo las 32 instrucciones estándar; HALT se prueba aparte.

**Restricciones que impone**

- El opcode de HALT es una constante compartida hardware/software: se define en `docs/protocolo.md` y se refleja en `du_defs.vh` / `control_unit.v` e `isa/instrucciones.py` (PRD §13).
- El ensamblador acepta `halt` como mnemónico nativo y agrega uno al final si falta (R-PR-1, ADR-013).
- El `du_loader` rellena con `0x0000000B` las posiciones de IMEM que no carga el programa (ADR-009).

## Referencias

- PRD §2.2 (fila 33), §6 (R-EJ-3 a R-EJ-5, R-PR-1), §8 (ADR-004), §14 (A2).
- _The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA_ — mapa de opcodes base (espacio _custom-0_) y la palabra `0x00000000` como instrucción ilegal.
