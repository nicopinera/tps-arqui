# ADR-007 — Estrategia de riesgos de datos y banco de registros

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-202, Hito 3
- **Relacionados:** ADR-001 (no usar el flanco de bajada), ADR-006 (resolución de saltos en EX con operandos forwardeados)

## Contexto

El enunciado enumera los tipos de riesgo, pero no exige ninguna solución concreta (PRD §14, A8). En este pipeline los riesgos de datos aparecen cuando una instrucción lee en ID un registro que todavía está escribiendo una instrucción anterior que no llegó a WB:

| Caso                                         | Ejemplo                                     | Distancia |
| -------------------------------------------- | ------------------------------------------- | --------- |
| ALU → ALU, instrucción siguiente             | `add x1,x2,x3` / `sub x4,x1,x5`             | 1         |
| ALU → ALU, dos instrucciones después         | `add x1,…` / `…` / `sub x4,x1,x5`           | 2         |
| Load → uso inmediato (load-use)              | `lw x1,0(x2)` / `add x3,x1,x4`              | 1         |
| Dato de un store recién calculado            | `add x1,…` / `sw x1,0(x2)`                  | 1 o 2     |
| Escritura y lectura del banco en el mismo ciclo | instrucción en WB escribe `x5`, la de ID lee `x5` | 3   |

## Decisión

### Forwarding completo + stall solo para load-use

- **Unidad de forwarding** (`forwarding_unit.v`) en EX, para cada operando (`rs1` → `fwd_a`, `rs2` → `fwd_b`):
  - `10` = desde EX/MEM (resultado de la ALU de la instrucción anterior), si `EX/MEM.reg_write && EX/MEM.valid && EX/MEM.rd != 0 && EX/MEM.rd == ID/EX.rsN`.
  - `01` = desde MEM/WB (resultado de ALU, dato de memoria o `PC+4`, según `result_src`), con la misma condición sobre MEM/WB.
  - `00` = valor leído del banco en ID.
  - **EX/MEM tiene prioridad sobre MEM/WB**, porque es el valor más reciente.
- El operando `rs2` forwardeado alimenta tanto el multiplexor de la ALU como el `store_data` que viaja a MEM. Así el caso del store se resuelve sin lógica adicional.
- Nunca se forwardea un "resultado" con destino `x0` ni desde un latch con `valid = 0`.
- **Unidad de riesgos** (`hazard_unit.v`) en ID: si `ID/EX.mem_read && ID/EX.valid && ID/EX.rd != 0 && (ID/EX.rd == IF/ID.rs1 || ID/EX.rd == IF/ID.rs2)`, entonces:
  - se congelan el PC e IF/ID durante 1 ciclo,
  - se inserta una burbuja en ID/EX (`valid = 0`, controles de escritura en 0),
  - en el ciclo siguiente el dato llega por forwarding desde MEM/WB.
- Para no generar stalls falsos, la comparación usa banderas del decodificador que indican si la instrucción realmente lee `rs1` / `rs2` (por ejemplo, `lui` y `jal` no leen ninguno, y los tipo I no leen `rs2`). Se detalla en la tabla de control de US-103.
- **Load seguido de store que guarda el valor cargado** (`lw x1` / `sw x1`): se trata como load-use (1 stall). No se agrega forwarding MEM→MEM.

### Banco de registros: bypass interno

- El banco escribe en el **flanco de subida**, como todo el diseño.
- Si en el mismo ciclo `wr_en && wr_addr == rd_addr && wr_addr != 0`, el puerto de lectura devuelve `wr_data` en lugar del contenido almacenado.
- `x0` se lee siempre como 0.

## Alternativas consideradas

**Estrategia de riesgos**

| Opción                                            | Ventajas                                                                                     | Desventajas                                                                                       |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| (a) Solo stalls                                   | Hardware mínimo: solo detección y congelamiento                                              | Hasta 2–3 ciclos perdidos por dependencia; programas mucho más lentos; poco interesante de mostrar |
| **(b) Forwarding completo + stall load-use** (elegida) | Solo pierde 1 ciclo en load-use; es la solución estándar del libro; muestra los tres mecanismos (forwarding, stall, flush) | Multiplexores de 3 entradas en EX que pueden quedar en el camino crítico                          |
| (c) NOPs insertados por el ensamblador            | Cero hardware                                                                                | No resuelve el problema en hardware; un programa escrito a mano sin NOPs da resultados incorrectos |

**Escritura y lectura del banco en el mismo ciclo**

| Opción                                  | Ventajas                                                     | Desventajas                                                                                                                  |
| --------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **(a) Bypass interno** (elegida)         | Un solo flanco; un comparador y un multiplexor               | Agrega un multiplexor en el camino de lectura de ID                                                                          |
| (b) Escribir en el flanco de bajada      | Es la solución del libro                                     | Usa ambos flancos y deja medio período para la escritura y medio para la lectura; discutible frente a "no intervenir el clock" (ADR-001) |
| (c) Tercer camino de forwarding WB → ID  | Toda la lógica de forwarding en un solo lugar                | Más señales entre etapas para un caso que el banco resuelve localmente                                                       |

## Consecuencias

**Positivas**

- La única dependencia de datos que cuesta un ciclo es load-use.
- Los tres mecanismos que pide analizar el enunciado (forwarding, stall y flush) existen y se pueden mostrar en la GUI gracias a las señales `stall`, `fwd_a`, `fwd_b` del snapshot (ADR-017).
- Un solo flanco de reloj en todo el diseño.
- Los saltos resueltos en EX (ADR-006) usan los operandos ya forwardeados, sin lógica extra.

**Negativas**

- Los multiplexores de forwarding en la entrada de la ALU y la comparación de branches en EX probablemente formen parte del camino crítico (se mide en US-601).
- La combinación de stall, flush y `i_enable` necesita una prioridad clara (ADR-006) y pruebas específicas.

**Restricciones que impone**

- Los latches tienen que llevar `rs1`, `rs2` y `rd` hasta donde los necesitan las unidades de forwarding y de riesgos (PRD §3.2).
- El stall solo actúa cuando `i_enable = 1`: con el núcleo congelado no se inserta ninguna burbuja (ADR-001).
- US-304 cubre: EX/MEM→EX, MEM/WB→EX, doble dependencia (prioridad EX/MEM), load-use, store con dato forwardeado, load→store, destino `x0` (no se forwardea) y escritura/lectura simultánea del banco.

## Referencias

- PRD §2.3 (riesgos de datos), §3.2 (señales de riesgo), §8 (ADR-007), §14 (A8); US-202, US-301, US-302, US-304.
- Patterson & Hennessy, _Computer Organization and Design — RISC-V Edition_, cap. 4 (forwarding y riesgos de datos).
