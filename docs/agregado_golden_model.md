# Agregado: modelo del pipeline ciclo a ciclo (US-306)

- **Estado:** propuesto, fuera del PRD original
- **Fecha:** 2026-11-19
- **Dependencias:** US-103 (`tabla_control.md`, `riscv_core.md`), US-108 (golden model), US-409 (`FakeTransport`), ADR-006, ADR-007, ADR-017
- **Esfuerzo estimado:** M (unas 300 líneas de modelo, más los tests)

## 1. Por qué

Hoy hay un solo modelo de referencia: el **golden model de ISA** (`iss/golden_model.py`). Ejecuta una instrucción entera por paso y no sabe nada del pipeline.

Eso tiene dos consecuencias:

1. **El modo simulado de la GUI no muestra riesgos.** `FakeTransport` corre el golden model y arma el snapshot a mano (`_snapshot()`): llena solo `pc`, `instr` y `valid` de cada latch. Las señales de control, `funct3`, `rd`, `alu_result`, etc. quedan en 0, y `stall`, `flush_*` y `fwd_*` siempre en 0. Por eso en simulado no se ven las burbujas de load-use, los branches tomados ni los flush. Las vistas están bien; no les llega nada que mostrar.
2. **Verificar compara solo el estado final.** Si el núcleo en Verilog da un registro mal, sabemos _que_ falló, pero no _en qué ciclo_ ni _qué señal_.

## 2. Conceptos

| Término                                     | Qué es                                                                                                                                                               |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Modelo de ISA** (golden model)            | Simula la arquitectura visible: registros, memoria, PC. Un paso = una instrucción. Sirve para el resultado final. Ejemplo real: Spike.                               |
| **Modelo ciclo a ciclo** (_cycle-accurate_) | Simula la microarquitectura: el PC, los 4 latches, la Hazard Unit y el forwarding. Un paso = un flanco de reloj. Ejemplos reales: gem5, co-simulación con Verilator. |
| **Lockstep**                                | Correr el modelo y la placa a la par y comparar el estado en **cada** ciclo. Encuentra la primera divergencia.                                                       |
| **Combinacional / secuencial**              | Combinacional: depende solo de las entradas del ciclo (ALU, Hazard Unit). Secuencial: guarda estado y cambia en el flanco (PC, latches, banco de registros).         |
| **Error de modo común**                     | El modelo y el RTL tienen el mismo error porque salieron de la misma lectura de la spec, y la comparación entre ellos no lo detecta.                                 |

## 3. Qué se construye

El estado del modelo es el PC, los 4 latches (`LatchIFID`, `LatchIDEX`, `LatchEXMEM`, `LatchMEMWB`, los mismos del protocolo), el banco de registros, la DMEM, el bitmap de memoria usada y el contador de ciclos.

`ciclo()` hace lo mismo que el hardware en un período de reloj:

1. Calcula todo lo combinacional con el estado **actual**: control, inmediato, forwarding, ALU, `branch_cmp`, Hazard Unit.
2. Arma el snapshot de este ciclo: los latches actuales y las señales de riesgo.
3. Calcula el estado siguiente de todos los elementos secuenciales y lo actualiza **de una vez**, como un flanco. No hay que escribir un latch y después leerlo en el mismo ciclo.

| Pieza                         | Qué hace                                                                                                     | Spec                       | Se puede reusar                 | Tamaño |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------- | ------------------------------- | ------ |
| Unidad de control + `imm_gen` | Palabra → señales de control e inmediato                                                                     | `tabla_control.md`, US-203 | `decode_*` de `isa/formatos.py` | ~60    |
| Banco con bypass              | Si WB escribe el registro que lee ID, ID ve el valor nuevo                                                   | ADR-007, US-202            | —                               | ~10    |
| ALU y `branch_cmp`            | Las operaciones de la ALU y `eq`/`ne`                                                                        | US-201, ADR-019            | `_ALU` del golden model         | ~10    |
| `store_align` / `load_extend` | sb/sh/sw, lb/lbu/lh/lhu/lw, little-endian                                                                    | US-205, ADR-018            | lógica del golden model         | ~20    |
| **Forwarding Unit**           | `fwd_a`/`fwd_b`: `10` desde EX/MEM, `01` desde MEM/WB, gana EX/MEM, nunca con `rd = 0` ni productor inválido | US-301                     | —                               | ~15    |
| **Hazard Unit**               | Load-use → stall; `jal` en ID → flush IF/ID; branch tomado o `jalr` en EX → flush IF/ID e ID/EX              | US-302, US-303, ADR-006    | —                               | ~20    |
| `ciclo()`                     | Prioridades (`riscv_core.md` §3), burbujas, HALT/ilegal, `stop_fetch` (ABORT), contador                      | US-210, US-303             | —                               | ~100   |

## 4. Decisiones a fijar antes de escribir código

El modelo obliga a dejar por escrito cosas que hoy son ambiguas. Si no se fijan, el modelo y el RTL pueden diferir en un ciclo sin que ninguno esté "mal". Cada una se documenta acá (o en un ADR) cuando se elija.

| #   | Decisión                               | Alternativas | Propuesta                                                                                                           |
| --- | -------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------- |
| D1  | **Qué muestra el snapshot** ✅         | —            | **Fijada:** el estado actual y los riesgos de este ciclo (lo que pasa en el próximo flanco)                         |
| D2  | **En qué ciclo termina** ✅            | —            | **Fijada:** en el flanco en que el HALT/ilegal sale de WB; ese flanco cuenta y deja los 4 latches con `valid = 0`   |
| D3  | **Dónde queda el PC al terminar** ✅   | —            | **Fijada:** congelado por `halt_fetch` en (dirección del HALT) + 4                                                  |
| D4  | **Desde cuándo cuenta `ciclos`** ✅    | —            | **Fijada:** 0 después de LOAD/RESET, +1 por flanco con enable. Falta confirmarlo contra la Debug Unit real (Hito 3) |
| D5  | **Qué es un Paso en modo simulado** ✅ | —            | **Fijada:** (a) un ciclo, como la placa. Los tests con cuentas se actualizaron con valores calculados a mano (§8)   |
| D6  | **El golden model de ISA sigue** ✅    | —            | **Fijada:** (a) queda como control independiente (RUN de `verify_board` y el paso 5)                                |

## 5. Pasos chicos y verificables

Cada paso se cierra con sus tests en verde y `make check-py` limpio.

| Paso | Qué                                                                                                                                                                      | Cómo se verifica                                                                                                                     |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 1 ✅ | **Unidad de control + `imm_gen`** (`controlar(palabra) -> Control`, `inmediato(palabra, imm_type)`)                                                                      | Test parametrizado con las 33 filas de `tabla_control.md` + palabras ilegales (`halt = illegal = 1`)                                 |
| 2 ✅ | **Pipeline del Hito 2:** IF, ID, EX, MEM, WB y los latches, con flush básico (branch/`jalr` en EX, `jal` en ID), HALT/ilegal y bypass del banco; sin forwarding ni stall | Programas con NOPs entre dependencias: estado final = golden model; ciclos = instrucciones + 4 + 2·(branches tomados + jalr) + 1·jal |
| 3 ✅ | **Forwarding Unit**                                                                                                                                                      | Vectores de US-301 AC1–AC7; `fwd_ex_mem.asm` = golden model sin NOPs                                                                 |
| 4 ✅ | **Hazard Unit (load-use), prioridades completas y `stop_fetch`**                                                                                                         | US-302 AC1–AC5, US-303 AC1–AC10; `load_use.asm` (1 stall por caso), `branch_taken.asm`, `llamadas.asm`                               |
| 5 ✅ | **Todo `asm/` contra el golden model**                                                                                                                                   | Para cada `.asm` (salvo `asm/errores/`): registros, memoria usada y motivo iguales al ISS                                            |
| 6 ✅ | **`FakeTransport` usa el modelo:** un Paso = un ciclo; RUN corre ciclos; ABORT usa `stop_fetch`                                                                          | Tests de protocolo existentes, ajustados (§8); en la GUI se ven stalls, flush y forwarding en simulado                               |
| 7 ✅ | **`verify_board --step`:** lockstep placa vs. modelo                                                                                                                     | Reporta el primer ciclo distinto y los campos que difieren ("ciclo 37: `fwd_a` = 00, se esperaba 10")                                |

Los pasos 1 a 5 no tocan nada existente. El 6 cambia el comportamiento del modo simulado. El 7 recién tiene sentido cuando exista el núcleo en Verilog.

**Estado (cerrado):** los 7 pasos están hechos, con `make check-py` limpio (909 tests). Notas del cierre:

- **US-303 AC7** ("branch tomado mientras hay un stall de load-use en ID") no se puede dar en este diseño: el stall exige un load en EX, y el branch se resuelve en EX; no pueden estar los dos a la vez. No tiene test.
- **Cuentas a mano (AC3):** `load_use` 14, `fwd_ex_mem` 18, `llamadas` 19, `branch_taken` 33, `fibonacci` 115 (89 + 4 + 2·11).
- **`verify_board --step` con `--fake`** pasa siempre por construcción (placa y modelo son el mismo código): sirve para probar el camino, no al modelo. El valor aparece con la placa real.
- **`_alu` del modelo reusa la ALU del golden model** (`shortcut:` en el código): un error en esa tabla sería de modo común para el paso 5.

## 6. Archivos

| Archivo                                                | Nuevo / cambia | Contenido                                                                                                      |
| ------------------------------------------------------ | -------------- | -------------------------------------------------------------------------------------------------------------- |
| `TP3/tools/riscv_toolkit/isa/control.py`               | nuevo          | `Control` (dataclass), `controlar()`, `inmediato()`. Solo stdlib (lo controla `tests/isa/test_solo_stdlib.py`) |
| `TP3/tools/riscv_toolkit/iss/pipeline_model.py`        | nuevo          | `ModeloPipeline` con `ciclo() -> Snapshot`, `forwarding()`, `riesgos()`                                        |
| `TP3/tools/tests/isa/test_control.py`                  | nuevo          | Las 33 filas de la tabla + ilegales                                                                            |
| `TP3/tools/tests/iss/test_pipeline_model.py`           | nuevo          | Vectores de US-301/302/303, cuentas de ciclos, comparación con el golden model para todo `asm/`                |
| `TP3/tools/riscv_toolkit/protocol/fake_transport.py`   | cambia         | Usa `ModeloPipeline` en vez de `GoldenModel` + `_snapshot()` a mano                                            |
| `TP3/tools/scripts/verify_board.py`                    | cambia         | Opción `--step` en lockstep                                                                                    |
| `docs/agregado_golden_model.md`                        | este archivo   | Se completa con las decisiones de §4                                                                           |
| `TP3/CHANGELOG.md`, `docs/guias/guia-riscv-toolkit.md` | cambian        | Entrada y sección nueva al cerrar                                                                              |

## 7. Riesgo principal: error de modo común

Si el modelo y el RTL se escriben con la misma lectura de la spec, pueden tener el mismo error y coincidir igual en lockstep. Defensas:

- **Contra el golden model de ISA (paso 5):** el pipeline no puede cambiar resultados. El golden model no comparte código de riesgos con el modelo nuevo, así que es un control independiente.
- **Contra cuentas a mano (paso 4):** los ciclos de los programas de riesgos se calculan en papel:

  ```text
  ciclos = instrucciones + 4 (llenar el pipeline) + stalls
         + 2 · (branches tomados + jalr) + 1 · jal  (± el ajuste que fije D2)
  ```

- **Contra los criterios de aceptación de US-301 a US-303:** están escritos como casos concretos; se pasan como vectores al modelo antes de existir el Verilog.

## 8. Impacto en lo que ya existe

- **Tests que esperan cuentas de ciclos del modo simulado** (por ejemplo `tests/scripts/test_verify_board.py`: `fibonacci` espera 89 ciclos). Con un Paso = un ciclo, el número cambia al del pipeline real. Se actualizan con el valor calculado a mano, no copiando lo que dé el modelo.
- **`ui/historial.py`:** "quién escribió qué" hoy devuelve "no se sabe" en simulado porque los latches vienen vacíos. Con el modelo, el modo simulado pasa a tener `reg_write`, `rd` y `mem_write` reales y la atribución empieza a funcionar sin cambios.
- **Resumen:** el CPI en simulado deja de ser 1 y muestra el reparto real (útiles, llenado, stall, flush).
- **Límite de RUN en simulado:** hoy `FakeTransport` corta por cantidad de instrucciones (`max_instr`). Con el modelo corta por ciclos, y el límite tiene que contemplar el CPI > 1.

## 9. Quién escribe qué

Según el acuerdo del proyecto (el núcleo lo escribe Nico):

| Lo escribe Nico (`TODO(nico)`)                                    | Lo arma Claude                                                          |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------- |
| ~~`controlar()` e `inmediato()`~~ (las escribió Claude, a pedido) | Esqueleto de `control.py` y `pipeline_model.py` con firmas y docstrings |
| Forwarding Unit y Hazard Unit                                     | Tests de los pasos 1 a 5 (tabla, vectores de AC, golden model)          |
| `ciclo()`: etapas, prioridades, HALT, `stop_fetch`                | Conexión con `FakeTransport` y `verify_board --step` (pasos 6 y 7)      |
| Decisiones D1–D6                                                  | Documentación, CHANGELOG, guía                                          |

## 10. Criterios de aceptación

- **AC1.** `controlar()` coincide con las 33 filas de `tabla_control.md` en todas las señales que la tabla no marca con `—`; una palabra ilegal da `halt = illegal = 1` y nada más.
- **AC2.** Para todos los `.asm` de `TP3/asm/` (salvo `errores/`), el estado final del modelo (registros, memoria usada, motivo) es igual al del golden model.
- **AC3.** `load_use.asm`, `branch_taken.asm`, `fwd_ex_mem.asm` y `llamadas.asm` terminan en la cantidad de ciclos calculada a mano (§7).
- **AC4.** Cada criterio de aceptación de US-301, US-302 y US-303 tiene un test contra el modelo.
- **AC5.** Al terminar, los 4 latches tienen `valid = 0` (US-210 AC2).
- **AC6.** En modo simulado, un Paso avanza un ciclo, y la GUI muestra stall, flush y forwarding en los ciclos que corresponden (checklist manual en `docs/manual/checklist_ui.md`).
- **AC7.** Las decisiones D1–D6 están escritas en este documento antes de cerrar el paso 4.
