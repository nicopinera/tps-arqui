# ADR-017 — Formato de volcado de latches (layout del snapshot)

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-103, US-405
- **Relacionados:** ADR-003 (trama `SNAPSHOT`), ADR-007 (señales de riesgo), ADR-008 (memoria usada), ADR-012 (GUI)

## Contexto

El enunciado pide enviar a la PC "el contenido de los latches intermedios", sin decir qué campos (PRD §14, A4). El snapshot es el contrato más sensible entre hardware y software: si cambia un campo de un latch, cambian el serializador (`du_dumper.v`), el decodificador (`protocol/snapshot.py`) y la vista de la GUI.

El contenido de cada latch se propone en PRD §3.2 y se congela en US-103. Este ADR decide **cómo** se serializa ese contenido y en qué orden va cada bloque del snapshot.

## Decisión

### Principios

- **Campo a campo, alineado a byte:** cada campo multi-bit ocupa una cantidad entera de bytes (por ejemplo, `rd` de 5 bits ocupa 1 byte; `pc` ocupa 4 bytes).
- **Las señales de 1 o 2 bits se agrupan en bytes de flags** con un orden de bits fijo, para no gastar un byte por cada bit de control.
- **Little-endian** en todos los campos de más de un byte (como RISC-V y como el resto del protocolo).
- **Orden fijo**, definido una sola vez en `docs/protocolo.md` e implementado en `du_dumper.v` y en `protocol/snapshot.py`.
- La **versión del formato** se devuelve en el `PING` (ADR-003); cualquier cambio de layout incrementa la versión.
- **Se incluye `instr`** (copia de la instrucción) en ID/EX, EX/MEM y MEM/WB, aunque el datapath no la necesite, para que la GUI muestre qué instrucción hay en cada etapa. Se controla con el parámetro `DEBUG_TRACE` (1 por defecto). Con `DEBUG_TRACE = 0` el campo se envía en cero, para que el layout no cambie.
- El snapshot siempre se toma con el núcleo congelado: todos los valores corresponden al mismo ciclo (R-DU-3).

### Orden del payload `SNAPSHOT`

| #   | Bloque               | Contenido                                                                                       | Tamaño                |
| --- | -------------------- | ----------------------------------------------------------------------------------------------- | --------------------- |
| 1   | Cabecera             | estado de la Debug Unit (1 B), contador de ciclos (4 B), PC actual (4 B)                         | 9 B                   |
| 2   | Riesgos del ciclo    | flags: `stall`, `flush_if_id`, `flush_id_ex`, `fwd_a[1:0]`, `fwd_b[1:0]`                          | 1 B                   |
| 3   | Banco de registros   | `x0` … `x31`, 4 B cada uno                                                                       | 128 B                 |
| 4   | IF/ID                | ver tabla siguiente                                                                             | ~13 B                 |
| 5   | ID/EX                | ver tabla siguiente                                                                             | ~31 B                 |
| 6   | EX/MEM               | ver tabla siguiente                                                                             | ~19 B                 |
| 7   | MEM/WB               | ver tabla siguiente                                                                             | ~18 B                 |
| 8   | Memoria usada        | cantidad de palabras `K` (2 B) + `K` × [dirección (2 B) + dato (4 B)], en orden creciente (ADR-008) | 2 + 6·K B             |
|     | **Total típico**     |                                                                                                 | **~221 B + 6·K**      |

### Layout de los latches (propuesta, se congela en US-103)

| Latch      | Campos en orden                                                                                                                                                         | Bytes |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| **IF/ID**  | `pc` (4), `pc_plus4` (4), `instr` (4), flags: `valid`                                                                                                                   | 13    |
| **ID/EX**  | `pc` (4), `pc_plus4` (4), `rs1_data` (4), `rs2_data` (4), `imm` (4), `rs1` (1), `rs2` (1), `rd` (1), `funct3` (1), `alu_op` (1), flags 1: `valid`, `reg_write`, `mem_read`, `mem_write`, `alu_src`, `branch`, `jump`, `jalr`; flags 2: `halt`, `illegal`, `funct7_b5`, `result_src[1:0]`; `instr` (4) | 31    |
| **EX/MEM** | `alu_result` (4), `store_data` (4), `pc_plus4` (4), `rd` (1), `funct3` (1), flags: `valid`, `halt`, `illegal`, `reg_write`, `mem_read`, `mem_write`, `result_src[1:0]`; `instr` (4)   | 19    |
| **MEM/WB** | `alu_result` (4), `mem_data` (4), `pc_plus4` (4), `rd` (1), flags: `valid`, `halt`, `illegal`, `reg_write`, `result_src[1:0]`; `instr` (4)                                         | 18    |

El orden exacto de los bits dentro de cada byte de flags se fija en `docs/protocolo.md`.

## Alternativas consideradas

| Opción                                            | Ventajas                                                                                         | Desventajas                                                                                                          |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| **(a) Campo a campo, alineado a byte** (elegida)  | Fácil de decodificar con `struct` en Python; legible en un volcado hex; un campo que crece dentro de su byte no corre a los demás | Unos bytes más que empaquetar a bit                                                                                  |
| (b) Bus plano empaquetado a bit                   | Mínimo de bytes; el `du_dumper` solo desplaza el bus                                              | Decodificación frágil; cualquier cambio de ancho corre todos los campos siguientes; ilegible en hex                  |
| (c) Tipo-longitud-valor (TLV)                     | Extensible sin romper compatibilidad                                                             | Más bytes y más lógica en hardware; innecesario con un formato versionado                                            |

**Copia de `instr`**

| Opción                                        | Ventajas                                                        | Desventajas                                                                                                    |
| --------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **(a) Sí, con `DEBUG_TRACE`** (elegida)       | La GUI muestra la instrucción real de cada etapa, incluso con flush y stall | 96 FF extra (justificados como lógica de depuración en el informe)                                             |
| (b) Solo el PC por etapa, la PC desensambla   | Sin FF extra                                                    | Depende de que la imagen de la PC coincida con la IMEM; ID/EX y siguientes no tienen hoy el PC en todos los latches |

## Consecuencias

**Positivas**

- Un snapshot típico (~221 B + pocas palabras) tarda ~130 ms a 19200 bps (ADR-002): cumple NFR-4.
- `Snapshot.from_bytes` es una secuencia de lecturas con `struct.unpack_from`, fácil de probar con las capturas de US-405.
- La GUI tiene todo lo necesario para mostrar burbujas (`valid`), riesgos (`stall`, `flush_*`, `fwd_*`) y la instrucción de cada etapa.

**Negativas**

- Cualquier cambio en los latches después de US-103 obliga a tocar tres lugares (RTL, dumper y Python) y a subir la versión del formato.
- El `du_dumper` tiene que conocer el layout campo por campo (o recibir un bus ya ordenado desde el núcleo).

**Restricciones que impone**

- `docs/protocolo.md` contiene la tabla completa de offsets y un snapshot de ejemplo en hex (US-104, AC2: la suma de tamaños coincide con el campo `longitud`).
- Hay un test en Python que verifica que el tamaño calculado del layout coincide con el declarado en `protocolo.md`.
- Un latch con `valid = 0` se envía igual, con todos sus campos; la GUI lo muestra como burbuja.

## Referencias

- PRD §3.2, §3.5, §6 (R-DU-3), §8 (ADR-017), §14 (A4); US-103, US-104, US-405, US-410.
