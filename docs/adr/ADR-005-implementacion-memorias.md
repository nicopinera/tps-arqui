# ADR-005 — Implementación de memorias

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-204, US-210
- **Relacionados:** ADR-001 (clock enable), ADR-008 (tamaños), ADR-009 (limpieza de DMEM), ADR-016 (frecuencia)

## Contexto

El procesador necesita dos memorias separadas (Harvard, para evitar el riesgo estructural entre IF y MEM):

- **IMEM:** la escribe la Debug Unit durante `LOAD` y la lee IF en cada ciclo.
- **DMEM:** la leen y escriben los loads/stores en MEM, y la Debug Unit la lee para el volcado (y la escribe para limpiarla, ADR-009).

En el Artix-7 hay dos formas de implementarlas, y la elección cambia el diseño de IF y MEM:

- **Memoria distribuida** (construida con LUTs): lectura **combinacional**, escritura sincrónica.
- **Block RAM (BRAM)**: bloques dedicados de 18/36 Kb con lectura **sincrónica** (el dato aparece un ciclo después de presentar la dirección).

El enunciado sugiere investigar los IP de memoria de Vivado, pero no exige usarlos. Con los tamaños de ADR-008 (256 palabras cada una), las dos opciones entran holgadas en el XC7A35T.

## Decisión

**IMEM y DMEM se implementan como memoria distribuida inferida** (código Verilog con un arreglo `reg [31:0] mem [0:DEPTH-1]`, lectura con `assign` y escritura en `always @(posedge clock)`).

- **IMEM**
  - Puerto de lectura combinacional para IF: `instr = imem[pc[ADDR_BITS+1:2]]`.
  - Puerto de escritura sincrónico para la Debug Unit (`i_imem_we`, `i_imem_addr`, `i_imem_wdata`), habilitado solo en `IDLE` / `HALTED` / `LOADING`.
- **DMEM**
  - Puerto de lectura combinacional para MEM (el núcleo) y un segundo puerto de lectura combinacional para la Debug Unit (volcado). Vivado replica la memoria para obtener la segunda lectura.
  - Un único puerto de escritura sincrónico con un multiplexor: lo usa el núcleo (stores, con `i_enable`) o la Debug Unit (limpieza de ADR-009). No hay conflicto porque la Debug Unit solo escribe con el núcleo detenido.
  - La escritura del núcleo maneja byte enables para `sb`/`sh` (ADR-018).
- Las memorias se pueden precargar en simulación con `$readmemh` (US-102).
- El datapath queda como el del libro de referencia: la instrucción y el dato leído están disponibles **en el mismo ciclo** en que se presenta la dirección, y pasan por el latch siguiente como cualquier otra señal.

## Alternativas consideradas

| Opción                                           | Ventajas                                                                                                                                             | Desventajas                                                                                                                                                                                              |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **(a) Memoria distribuida** (elegida)            | Datapath idéntico al del libro; no hay que realinear el PC; los stalls no necesitan enable en el puerto de lectura; simula sin IP; fácil de explicar | Consume LUTs; la lectura combinacional queda dentro del camino IF→IF/ID y MEM→MEM/WB y puede alargar el camino crítico; no escala a memorias grandes                                                     |
| (b) BRAM inferida, dual port, lectura sincrónica | No consume LUTs; muy rápida; es lo que sugiere el enunciado                                                                                          | Obliga a presentar a la IMEM el **próximo** PC (la salida de la BRAM hace de parte del latch IF/ID) y a leer en el flanco de fin de MEM; el puerto de lectura tiene que respetar `i_enable` y los stalls |
| (c) IP _Block Memory Generator_ (true dual port) | Configuración guiada, robusta                                                                                                                        | Mismos cambios de datapath que (b), más dependencia de un `.xci` versionado y del IP para simular                                                                                                        |
| (d) Mixto (IMEM distribuida, DMEM en BRAM)       | Mantiene IF simple                                                                                                                                   | Dos estilos de memoria distintos para explicar y probar; MEM se complica igual                                                                                                                           |

Se elige (a) porque baja el riesgo en la parte más difícil del proyecto, el pipeline con riesgos: la temporización de IF y MEM es la del libro, y el diagrama de US-103 no necesita una lógica especial para alinear el PC con una lectura sincrónica. El costo en LUTs es chico para 256 palabras, y el impacto en el camino crítico se mide en US-601.

## Consecuencias

**Positivas:**

- IF, MEM y la hazard unit se diseñan como en el libro: menos casos especiales y menos fuentes de bugs.
- Un stall congela el PC y el latch IF/ID con `i_enable` / `stall`, y la instrucción leída no cambia porque depende solo del PC. La restricción de ADR-001 sobre el enable del puerto de lectura de BRAM **no aplica**.
- La simulación no depende de modelos de IP: los testbenches corren igual en xsim y en Icarus (ADR-015).
- El volcado de la DMEM por la Debug Unit es combinacional: se pone una dirección y el dato está listo en el mismo ciclo.

**Negativas:**

- Consumo de LUTs: 256 × 32 bits de memoria distribuida ocupan del orden de 128 LUTs por puerto de lectura (con RAM256X1S), y la DMEM se replica para el segundo puerto. Sigue lejos del límite de NFR-3 (< 50 % de LUTs).
- La lectura combinacional suma retardo a las etapas IF y MEM; MEM ya tiene la extensión de signo de `lb`/`lh` detrás. Si en US-601 aparece en el camino crítico, la salida es bajar la frecuencia (ADR-016) o migrar a BRAM (alternativa b).
- No se usa la BRAM, que el enunciado sugiere investigar: en el informe se justifica la elección y se explica qué cambiaría con BRAM.
- La memoria distribuida no se puede limpiar con un reset de un ciclo: la limpieza de ADR-009 la recorre palabra por palabra.

**Restricciones que impone:**

- `DEPTH` y `ADDR_BITS` son parámetros (ADR-008); agrandar mucho las memorias obliga a reevaluar esta decisión.
- El puerto de escritura del núcleo se habilita con `mem_write && valid && i_enable` (R-EJ-6, ADR-001).
- El multiplexor del puerto de escritura de la DMEM selecciona la Debug Unit solo cuando el núcleo está detenido.
- En el informe (US-604) se reportan los LUTs que ocupan las memorias y si aparecen en el camino crítico.
