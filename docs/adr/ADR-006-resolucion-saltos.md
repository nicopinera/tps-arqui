# ADR-006 — Punto de resolución de saltos

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-303
- **Relacionados:** ADR-004 (HALT detrás de un salto), ADR-007 (forwarding), ADR-005 (lectura combinacional de IMEM)

## Contexto

Las instrucciones de control del enunciado son `beq`, `bne`, `jal` y `jalr`. Mientras no se sabe si un salto se toma ni adónde va, IF sigue buscando instrucciones. Si el salto se toma, esas instrucciones se tienen que descartar (flush). Cuanto antes se resuelva el salto, menos instrucciones se descartan, pero el hardware se complica:

| Instrucción  | Qué necesita para resolverse                           | ¿Depende de registros? |
| ------------ | ------------------------------------------------------ | ---------------------- |
| `jal`        | Destino `PC + imm`                                     | No                     |
| `jalr`       | Destino `(rs1 + imm) & ~1`                             | Sí (`rs1`)             |
| `beq`, `bne` | Comparar `rs1` con `rs2`; destino `PC + imm`           | Sí (`rs1`, `rs2`)      |

Resolver en ID algo que depende de registros exige llevar el forwarding hasta ID y agregar stalls cuando el registro lo produce la instrucción inmediatamente anterior (o un load dos instrucciones antes).

## Decisión

**Resolución mixta con predicción _not-taken_:**

- **Predicción:** IF siempre busca en `PC + 4`. No hay predictor ni tabla de saltos.
- **`jal` se resuelve en ID.** Un sumador en ID calcula `PC_ID + imm_J`; en ese mismo ciclo se redirige el PC y se hace flush de IF/ID (la instrucción buscada en IF se convierte en burbuja). **Penalidad: 1 ciclo.**
- **`beq`, `bne` y `jalr` se resuelven en EX**, con los operandos ya forwardeados (ADR-007):
  - `beq`/`bne`: comparador de igualdad dedicado sobre los operandos A y B de EX, en paralelo con la ALU (ADR-019).
  - `jalr`: el destino `(rs1 + imm) & ~1` se calcula en EX.
  - Si se toma el salto: se redirige el PC y se hace flush de IF/ID e ID/EX. **Penalidad: 2 ciclos.** Si un branch no se toma, no hay penalidad.
- La dirección de retorno de `jal`/`jalr` (`PC + 4`) viaja por `pc_plus4` en los latches y se escribe en WB con `result_src = PC+4`.

**Prioridades cuando coinciden varios eventos en el mismo ciclo** (de mayor a menor):

1. Salto tomado en EX: es la instrucción más vieja, así que su flush anula también a un `jal` que esté en ID y a un HALT recién detectado (R-EJ-4).
2. `jal` en ID.
3. Stall por load-use (ADR-007): si en el mismo ciclo hay un flush desde EX, gana el flush.
4. HALT detectado en ID: congela el PC, salvo que un salto más viejo lo anule.

## Alternativas consideradas

| Opción                                         | Penalidad (tomado)        | Ventajas                                                                                       | Desventajas                                                                                                                                |
| ---------------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| (a) Todo en EX                                 | 2 en todos                | Un único punto de redirección y flush; lo más simple                                           | `jal` paga 2 ciclos sin necesidad                                                                                                          |
| (b) Todo en ID                                 | 1 en todos                | Mínima penalidad                                                                               | Comparador y sumador en ID, forwarding hacia ID, stalls nuevos (ALU→branch y load→branch); ID se vuelve candidato fuerte a camino crítico |
| **(c) Mixto: `jal` en ID, resto en EX** (elegida) | `jal`: 1; resto: 2     | `jal` se adelanta gratis porque no depende de registros; los branches no necesitan forwarding hacia ID | Dos puntos de redirección del PC con prioridades entre ellos                                                                               |

**Predicción**

| Opción                                   | Ventajas                                                   | Desventajas                                                                     |
| ---------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Predict not-taken** (elegida)          | No agrega hardware; los branches no tomados no pagan nada  | Necesita flush cuando se toma el salto                                          |
| Stall hasta resolver                     | No hay instrucciones especulativas que anular              | Todos los branches pagan 2 ciclos, tomados o no; el flush hace falta igual para `jal` |

Se elige (c) con not-taken porque es la mejor relación entre penalidad y complejidad: el único costo extra frente a (a) es un sumador en ID y una regla de prioridad. La opción (b) queda en el roadmap como mejora.

## Consecuencias

**Positivas**

- No hace falta forwarding hacia ID ni stalls por dependencias de branches: la hazard unit solo maneja load-use (ADR-007).
- `jal` (y las pseudoinstrucciones `j` de ADR-013) cuestan 1 ciclo en lugar de 2.
- El comportamiento de cada tipo de salto es fácil de mostrar en la GUI y de explicar en el informe.

**Negativas**

- Hay dos fuentes de redirección del PC, así que el multiplexor del próximo PC tiene más entradas y una lógica de prioridad que hay que probar.
- Los branches tomados y `jalr` pierden 2 ciclos. En loops cortos el impacto es visible.

**Restricciones que impone**

- El multiplexor del próximo PC tiene cuatro fuentes: `PC + 4`, destino de `jal` (ID), destino de branch/`jalr` (EX) y PC congelado (stall/HALT/`i_enable = 0`).
- Los casos de US-304 incluyen: branch tomado y no tomado, `jal`, `jalr`, `jal` en ID con un branch tomado en EX en el mismo ciclo, y HALT detrás de un salto tomado.
- En el informe se documenta la penalidad de cada tipo de salto.

## Referencias

- PRD §2.3 (riesgos de control), §6 (R-EJ-3, R-EJ-4), §8 (ADR-006); US-303, US-304.
- Patterson & Hennessy, _Computer Organization and Design — RISC-V Edition_, cap. 4 (riesgos de control).
