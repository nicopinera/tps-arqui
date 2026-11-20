# Changelog

Todos los cambios relevantes del TP3 se registran en este archivo.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen el esquema de la sección 15 del PRD.

## [Unreleased]

### Added

- `hw/rtl/top.v`: el sistema integrado (UART + Debug Unit + núcleo) con el Clock Wizard (`hw/ip/clk_wiz_0/clk_wiz_0.xci`, 100 → 85 MHz), reset sincronizado que espera a `locked`, `COUNT_MAX` recalculado para 19200 bps a 85 MHz y LEDs de estado (READY, RUN/STEP, HALTED, error de paridad) (US-411, US-602).
- `hw/tb/top/tb_top_system.v`: un programa por la UART simulada al `top` (PING, LOAD, RUN, SNAPSHOT) contra el `.expected` del golden model, y `make sim-system` con toda la suite de `asm/` (US-411).
- `hw/tb/top/tb_top_sin_halt.v`: el experimento de qué pasa sin HALT (cola de un programa anterior, ILLEGAL y ABORT), con el log en `docs/informe/datos/experimento_sin_halt.txt` (US-407, US-604).
- `make impl` (`hw/scripts/impl_top.tcl`): síntesis, implementación y bitstream del `top` en contexto, con los reportes de timing, relojes, utilización por módulo, potencia y DRC en `hw/reports/top_*.rpt` (US-601, US-603).
- `make freq-sweep` (`hw/scripts/freq_sweep.tcl`, resultado en `hw/reports/freq_sweep.csv`) y `make clk-wiz MHZ=<f>` (`hw/scripts/gen_clk_wiz.tcl`); `hw/scripts/comun.tcl` con lo compartido entre scripts (US-602).
- `make reportes` (`tools/scripts/resumen_reportes.py`): lee los `.rpt` y el barrido sin Vivado y arma las tablas de `docs/informe/datos/reportes_vivado.md` (US-601, US-603).
- `tools/scripts/sesiones_defensa.py` y `docs/defensa/sesiones/*.json`: sesiones grabadas para el plan B de la defensa; `docs/defensa/guion.md` (US-605).
- `docs/manual/usuario.md` (US-604) y `docs/guias/guia-sintesis-sistema.md`.
- `docs/informe/`: `informe.md` (las 10 secciones y las 8 preguntas del enunciado), `timing.md` (camino crítico, skew, barrido y antes/después) y `metricas.md` (recursos por módulo, potencia, CPI y comparación con el TP2), con los datos de `docs/informe/datos/` (US-601 a US-604).
- `docs/guias/guia-reporte-timing.md`, parte 2: cuentas de setup y hold con el camino real, camino crítico, skew y CPR, jitter, MMCM/Clock Wizard, metaestabilidad y barrido de frecuencia.
- `.github/workflows/release.yml`: al pushear un tag `vX.Y` crea el release con la sección `[X.Y]` de este archivo como notas.
- Página **Datapath** de la GUI: el diagrama `docs/diagramas/datapath_pipeline.svg` con el valor de cada cable en el ciclo que se ve (medido del snapshot o calculado por el modelo), los latches marcados en stall/flush y el camino que elige cada mux (forwarding, PC, ALU, WB) pintado; zoom y arrastre. `scripts/gen_datapath.py` genera el fondo (PNG, con Edge) y el mapa de etiquetas, muxes y redes (`ui/assets/datapath/`); un test avisa si quedaron viejos.
- `ModeloPipeline.cables()` y `ModeloPipeline.desde_snapshot()`: las señales combinacionales de un ciclo (las de la Hazard Unit incluidas) calculadas desde el estado de un snapshot.
- `asm/riesgos/`: 12 programas cortos, uno por caso (forwarding EX/MEM, MEM/WB, distancia 3, el más nuevo gana, store, load-use con y sin stall, branch tomado y no tomado, `jal`, `jalr`, load-use + branch), con lo que hay que mirar en la GUI y los ciclos; un test verifica los ciclos del encabezado.
- `docs/guias/guia-riesgos-forwarding-hazard.md`: guía de estudio de los riesgos (estructurales, de datos, de control), la Forwarding Unit y la Hazard Unit, con cartas de pipeline de `load_use` y `branch_taken`, la cadena de prioridades y el Verilog de cada unidad.
- `iss/pipeline_model.py` (agregado US-306, pasos 2 a 5): modelo del pipeline ciclo a ciclo con Forwarding Unit, Hazard Unit (load-use), flush de branch/`jalr` en EX y `jal` en ID, HALT con `halt_fetch`, `stop_fetch` y bypass del banco; probado con los AC de US-301 a US-303, cuentas de ciclos a mano y todo `asm/` contra el golden model.
- `verify_board --step` en lockstep (agregado US-306, paso 7): en cada STEP compara el snapshot de la placa con el del modelo del pipeline y reporta el primer ciclo distinto y los campos que difieren (`comparar_ciclo`).
- `isa/control.py` (agregado US-306, paso 1): unidad de control (`controlar`) e `imm_gen` (`inmediato`) del pipeline, con tests que leen `docs/interfaces/tabla_control.md` fila por fila.
- Estructura de carpetas de `TP3/` (`hw/rtl`, `hw/constraints`) y `Makefile` con los objetivos de simulación pendientes de US-102 (US-101).
- Módulos UART del TP2 migrados sin cambios a `hw/rtl/uart/` (US-101).
- `hw/rtl/legacy/` con `alu_tp1.v`, `uart_interface.v` y `top_tp2.v` como referencia y prueba de humo de la migración (US-101).
- `hw/constraints/basys3.xdc` basado en las constraints del TP2 (US-101).
- `docs/guias/guia-herramientas.md`: lint con Verilator, simulación con Icarus Verilog y armado del proyecto de Vivado (US-101).
- `make lint`: lint obligatorio del RTL con Verilator (`hw/scripts/lint.sh`) (US-102).
- `make sim TB=<tb>` y `make sim-all`: simulación con Icarus Verilog y veredicto PASS/FAIL, con `WAVES=1` y `HEX=<ruta>` (`hw/scripts/sim.sh`) (US-102).
- `hw/tb/common/tb_utils.vh` (`check_eq`, `tb_finish`, `tb_init`, `tb_timeout`) y los testbenches `tb_uart_loopback` y `tb_readmemh` (US-102).
- `tools/`: proyecto uv `riscv-toolkit` (Python 3.13) con el paquete `riscv_toolkit`, configuración de `ruff`, `mypy` estricto, `pytest` con cobertura y `pip-audit` (US-102).
- `make setup`, `make test-py`, `make check-py`, `make check` y `make clean` (US-102).
- CI en GitHub Actions (`.github/workflows/ci.yml`): lint y simulación del RTL, y verificaciones de Python (US-102).
- `docs/diagramas/datapath_pipeline.drawio`/`.svg`: datapath segmentado de 5 etapas con los 4 latches, Forwarding Unit, Hazard Unit, `branch_cmp` y redirección del PC desde ID y EX (US-103).
- `docs/interfaces/tabla_control.md` (v0.1): señales de control de las 33 instrucciones y combinaciones `opcode`/`funct3`/`funct7` legales (US-103).
- `docs/interfaces/riscv_core.md` (v0.1): interfaz de `riscv_core` y layout de los buses de latches (`o_if_id` 104 b, `o_id_ex` 248 b, `o_ex_mem` 152 b, `o_mem_wb` 144 b) (US-103).
- `docs/diagramas/debug_unit_fsm.drawio`/`.svg`: máquina de estados de la Debug Unit con transiciones por comando, timeout y motivos de terminación (US-103).
- `docs/carta_pipeline_us103.md`: carta de pipeline de un programa de 10 instrucciones con forwarding EX/MEM, load-use y `beq` tomado (US-103).
- `docs/diagramas/arquitectura_sistema.drawio` y `docs/guias/guia-estudio-datapath.md`: vista general del sistema y guía de estudio del datapath (US-103).
- `docs/protocolo.md` (versión de protocolo `0x01`): contrato byte a byte PC ↔ Debug Unit (UART 8E1, comandos, tramas `[A5][tipo][len][payload][XOR]`, layout del snapshot de 221 + 6·K bytes, errores y ejemplos en hex) (US-104).
- `docs/diagramas/secuencia_protocolo.md`: diagrama de secuencia LOAD → STEP ×3 → RUN → snapshot (US-104).
- `docs/guias/guia-estudio-debug-unit.md`: guía de estudio de la máquina de estados de la Debug Unit (US-104).
- `tools/riscv_toolkit/protocol/comandos.py`: constantes del protocolo y enums `Comando`, `TipoTrama`, `ErrorNack`, `EstadoDU` y `Motivo` (US-104).
- `tools/scripts/gen_du_defs.py` y `hw/rtl/debug/du_defs.vh` (generado y versionado): las mismas constantes como `` `define `` de Verilog; un test verifica que el `.vh` está al día (US-104).
- `tools/riscv_toolkit/isa/`: tabla de las 33 instrucciones (`instrucciones.py`, con `HALT_OPCODE`/`HALT_WORD`), registros `x0`–`x31` (`registros.py`) y `encode_*`/`decode_*` de los formatos R, I, S, B, U y J con `ErrorCodificacion` (`formatos.py`) (US-105).
- `docs/interfaces/formatos.md` (v0.1): bits de cada campo y reordenamiento del inmediato por formato, contrato entre `formatos.py` e `imm_gen.v` (US-105).
- `tools/riscv_toolkit/assembler/`: ensamblador de dos pasadas `ensamblar(texto) -> Imagen` con lexer por expresiones regulares, parser con la sintaxis de cada mnemónico, etiquetas, pseudoinstrucciones `nop`/`mv`/`j`/`ret`, `.word`, HALT final automático, límite de 256 palabras, errores con número de línea (`ErrorEnsamblado`) y advertencias de accesos desalineados con base `x0` (US-106).
- `make gnu-ref` y `tools/tests/assembler/fixtures/todas_las_instrucciones.{asm,hex}`: referencia de GNU `as` para las 32 instrucciones estándar; `test_vs_gnu.py` verifica que el ensamblador produzca las mismas palabras (US-106).
- `docs/guias/guia-ensamblador.md` (etapas, pasadas, errores y decisiones de diseño) y `docs/guias/guia-regex.md` (expresiones regulares y la regex del lexer) (US-106).
- `tools/riscv_toolkit/disasm/disassembler.py`: `desensamblar(palabra, pc=None) -> str` con la sintaxis del ensamblador; `halt` para todo opcode custom-0, `.word 0x...` para las ilegales de `tabla_control.md` §3, y destino de branches y `jal` absoluto con `pc` (`0x1c`) o relativo sin él (`.+8`). Tests de ida y vuelta de las 33 instrucciones y de los casos ilegales (US-107).
- `tools/riscv_toolkit/assembler/salidas.py`: `a_hex` (una palabra por línea, para `$readmemh`), `a_bin` (`4·N` bytes little-endian, el payload de `LOAD`) y `a_lst(imagen, texto)` (dirección, palabra, línea y fuente, con las etiquetas en su renglón y la expansión de cada pseudoinstrucción). Un test carga el `.hex` con `tb_readmemh` si hay Icarus instalado (US-107).
- CLI `rvasm` como subcomando `asm` de `python -m riscv_toolkit` (`tools/riscv_toolkit/cli/rvasm.py`): `asm programa.asm [-o salida|-] [--format hex|bin|lst]`, formato deducido de la extensión de `-o` (por defecto `.hex` al lado de la entrada), errores y advertencias en stderr como `archivo:línea: ...`, y código de salida 1 ante errores de ensamblado o de archivo (US-107).
- `tools/riscv_toolkit/iss/golden_model.py`: `GoldenModel(imem_words)` ejecuta las 33 instrucciones de a una (`step`, `run(max_instr)` con `HALTED`/`ILLEGAL`/`TIMEOUT`) y da `estado_final() -> EstadoArquitectonico` (registros, memoria usada, PC y motivo). Arranca en cero con la IMEM rellena de HALT, ignora los bits bajos de los accesos desalineados con una advertencia y da la vuelta en las direcciones fuera de rango (ADR-008, ADR-009, ADR-018) (US-108).
- `tools/riscv_toolkit/iss/expected.py`: formato `.expected` (motivo, PC, `x0`–`x31` y pares dirección/dato de la memoria usada, una palabra hex por línea para `$readmemh`) con `a_expected` y `leer_expected` (US-108).
- CLI `rvsim` como subcomando `sim` de `python -m riscv_toolkit` (`tools/riscv_toolkit/cli/rvsim.py`): `sim programa.asm [--dump] [--expect salida.expected] [--max-instr N]`, código de salida 1 ante errores o `TIMEOUT` (US-108).
- `tools/tests/iss/`: tests por instrucción con valores borde, casos de terminación, ida y vuelta del `.expected` y programas de integración en `fixtures/` (US-108).
- `docs/guias/guia-golden-model.md`: cómo funciona el golden model, algoritmo de cada grupo de instrucciones y formato `.expected` (US-108).
- `hw/rtl/core/alu.v`: ALU combinacional de 32 bits (`NBIT`) con las 11 operaciones de ADR-019 seleccionadas por `alu_ctrl[3:0]`, sin overflow y con `o_zero` (no decide branches) (US-201).
- `hw/rtl/core/alu_control.v`: genera `alu_ctrl` a partir de `alu_op`, `funct3` y `funct7_b5` según `tabla_control.md` §4; en I-type el bit 30 solo distingue `srli`/`srai` (US-201).
- `hw/rtl/core/alu_defs.vh`: `localparam` compartidos `ALU_*` (codificados como `{funct7_b5, funct3}`, `PASS_B` = `1111`), `ALU_OP_*` y `F3_*` (US-201).
- `hw/tb/core/tb_alu.v` (55 vectores con los casos borde de AC1, verifica `o_result` y `o_zero`) y `hw/tb/core/tb_alu_control.v` (las 64 combinaciones de entrada más palabras reales de `addi`, `sub`, `srli`, `srai`) (US-201).

- `hw/rtl/core/reg_file.v`: banco de 32 × 32 bits con flip-flops, dos lecturas combinacionales con bypass interno WB→ID (ADR-007), escritura con `i_enable`, puerto de lectura para la Debug Unit (sin bypass), `x0` en 0 y borrado `i_clear` independiente de `i_enable` y con prioridad sobre la escritura (US-202).
- `hw/tb/core/tb_reg_file.v`: los 5 AC más la escritura y lectura de los 31 registros por los tres puertos (297 chequeos) (US-202).
- `hw/rtl/core/control_unit.v`: decodifica `opcode`/`funct3`/`funct7` en las señales de `tabla_control.md` §2, con un bloque de legalidad aparte según §3. HALT (cualquier palabra custom-0) da `halt = 1`; las ilegales dan `halt = illegal = 1` sin escrituras ni lecturas de registros (ADR-004, ADR-018) (US-203).
- `hw/rtl/core/imm_gen.v`: inmediato de 32 bits extendido en signo de los formatos I, S, B, U y J según `formatos.md` (US-203).
- `hw/rtl/core/control_defs.vh`: `localparam` de opcodes (`OP_HALT` sale de `du_defs.vh`), `funct7`, `funct3` de loads/stores/branches/`jalr`, `result_src` e `imm_type` (US-203).
- `tools/scripts/gen_imm_vectors.py` y `hw/tb/core/vectores/imm_gen{,_esperado}.hex` (generados y versionados): 68 instrucciones ensambladas con inmediatos positivos, negativos y extremos, y su inmediato esperado según `isa/formatos.py`; `test_imm_vectors_sync.py` verifica que estén al día (US-203).
- `hw/tb/core/tb_control_unit.v` (las 33 filas de la tabla, HALT custom-0, 24 palabras ilegales y barrido de los 128 opcodes) y `hw/tb/core/tb_imm_gen.v` (vectores cruzados con Python) (US-203).
- `hw/rtl/core/instr_mem.v`: IMEM de 256 palabras en memoria distribuida (LUTRAM) inferida, lectura combinacional por PC (los bits bajos y altos se ignoran), escritura sincrónica por el puerto de la Debug Unit y precarga opcional con `INIT_FILE` (ADR-005, ADR-008) (US-204).
- `hw/rtl/core/data_mem.v`: DMEM de 256 palabras en LUTRAM con escritura por byte (`i_be`), lectura combinacional para el núcleo y para la Debug Unit, un único puerto de escritura con mux (store del núcleo con `we && valid && enable` o limpieza en cero de la Debug Unit, que no marca), y bitmap de memoria usada con contador de 9 bits que se borra con `i_clear_used` (ADR-005, ADR-008) (US-204).
- `hw/tb/core/tb_instr_mem.v` (escritura y lectura de las 256 palabras, PC fuera de rango, escritura sincrónica, precarga) y `hw/tb/core/tb_data_mem.v` (AC2–AC5 contra un modelo de referencia de las 256 palabras, bitmap y contador) (US-204).
- `hw/rtl/core/store_align.v`: a partir de `funct3` y `addr[1:0]` genera los byte enables de `data_mem` y replica el dato de `sb`/`sh` en todos los bytes; `sh` ignora `addr[0]` y `sw` ignora `addr[1:0]` (ADR-018) (US-205).
- `hw/rtl/core/load_extend.v`: selecciona el byte o la media palabra de la palabra leída (little-endian) y la extiende con signo (`lb`, `lh`) o con ceros (`lbu`, `lhu`); los desalineados ignoran los bits bajos (ADR-018) (US-205).
- `hw/tb/core/tb_load_store_align.v`: `store_align` → `data_mem` → `load_extend` contra un modelo de referencia por byte; AC1–AC4 y las combinaciones tipo × offset de loads y stores (US-205).
- `hw/rtl/core/if_stage.v`: registro PC, mux de próximo PC con prioridad redirección de EX > `jal` en ID > `pc + 4` (ADR-006) e IMEM con su puerto de carga; el PC se congela con `i_stall`/`i_halt_fetch` salvo ante una redirección de EX (US-206).
- `hw/rtl/core/if_id_reg.v`: latch IF/ID (`pc`, `pc_plus4`, `instr`, `valid`) con reset, enable, flush (burbuja: `valid = 0`, `instr = NOP`) y stall; `INSTR_NOP` en `control_defs.vh` (US-206).
- `hw/tb/core/tb_if_stage.v`: AC1–AC6, `halt_fetch` con y sin redirección, reset con `i_enable = 0` y vuelta de la IMEM fuera de rango (US-206).
- `hw/rtl/core/id_stage.v`: extrae `rs1`, `rs2`, `rd`, `funct3` y `funct7_b5`, instancia `reg_file` (escritura desde WB y puerto de depuración por la etapa), `control_unit` e `imm_gen`, calcula el destino de `jal` (`pc + imm_J`) con `o_redirect_jal` en el mismo ciclo (ADR-006) y genera `o_halt_detected` para HALT o ilegal con `valid` (US-207).
- `hw/rtl/core/id_ex_reg.v`: latch ID/EX con los campos de PRD §3.2; con `i_flush`, `i_bubble` o `valid = 0` entra una burbuja (`valid = 0`, `instr = NOP`, todas las señales de control en 0); parámetro `DEBUG_TRACE` para el campo `instr` (US-207).
- `hw/tb/core/tb_id_stage.v`: AC1–AC4 con las palabras del ensamblador (R, I, shifts, load, store, `lui`, `jalr`, branches, `jal` con offset positivo y negativo, HALT e ilegales), banco a través de la etapa (bypass WB→ID, `x0`, escritura sin enable), flush, bubble, `i_enable = 0`, reset y `DEBUG_TRACE = 0` (US-207).
- `hw/rtl/core/ex_stage.v`: muxes de forwarding de 3 entradas para los dos operandos (`FWD_*` en `control_defs.vh`), mux `alu_src`, `alu_control` + `alu`, `branch_cmp` sobre los operandos forwardeados, destino de branch (`pc + imm`) y de `jalr` (`alu_result & ~1`) y `o_redirect` con `valid` (ADR-006) (US-208).
- `hw/rtl/core/branch_cmp.v`: comparador de igualdad de los branches, en paralelo con la ALU (ADR-019) (US-208).
- `hw/rtl/core/ex_mem_reg.v`: latch EX/MEM con los campos de PRD §3.2 (`store_data` = rs2 forwardeado), reset, enable y `DEBUG_TRACE`; no crea burbujas (US-208).
- `hw/tb/core/tb_ex_stage.v`: AC1–AC5 (R, I con imm negativo, dirección de load/store, `lui`, `beq`/`bne` adelante y atrás, `jalr` impar, los 4 valores de `fwd_a`/`fwd_b`, branch y `jalr` con `valid = 0`), EX/MEM con enable, reset y `DEBUG_TRACE = 0` (US-208).
- `hw/tb/core/tb_branch_cmp.v`: iguales, distintos por un bit en cada posición y aleatorios (US-208).
- `hw/rtl/core/mem_stage.v`: conecta `store_align`, `data_mem`, `dmem_bitmap` y `load_extend`, con los puertos de la Debug Unit de la DMEM (limpieza, borrado del bitmap, lectura con bit de usada y contador) (US-209).
- `hw/rtl/core/mem_wb_reg.v`: latch MEM/WB con los campos de PRD §3.2, reset, enable y `DEBUG_TRACE`; no crea burbujas (US-209).
- `hw/rtl/core/wb_stage.v`: mux `result_src` (ALU / memoria / PC+4), `o_wb_we = valid && reg_write` y `o_halt_retired`/`o_illegal_retired` (US-209).
- `hw/tb/core/tb_mem_wb.v`: MEM → MEM/WB → WB con `sw`/`sb`/`sh` verificados por el puerto de la Debug Unit, los 5 loads con extensión, `add`, `jal`, store sin escritura en el banco, HALT e ilegal retirados un ciclo, burbuja, `i_enable = 0`, reset y `DEBUG_TRACE = 0` (US-209).
- `hw/rtl/core/riscv_core.v`: núcleo completo con la interfaz de `riscv_core.md`: etapas y latches, enable efectivo (`i_enable && !o_halted`), `halt_fetch` pegajoso (se borra con una redirección de EX: HALT especulativo), `o_halted`/`o_illegal`, `i_flush_all`, `i_stop_fetch` (ABORT), flush básico, señales de riesgo (`o_stall = 0`, `fwd = 00` hasta el Hito 3) y buses planos de los latches con el layout del snapshot (US-210).
- `asm/tests/h2/`: 8 programas (`r_type`, `i_arith`, `shifts`, `loads_stores`, `lui`, `branches`, `jumps`, `illegal`) con 3 `nop` entre instrucciones dependientes; después de cada salto tomado hay instrucciones que escribirían registros o memoria (US-210).
- `hw/tb/core/tb_core_programs.v`: carga un programa como un `LOAD`, corre hasta `o_halted` y compara motivo, PC, registros y memoria usada con el `.expected` del golden model; pipeline vacío al terminar (AC2), nada posterior al HALT llega a EX (AC3), enable aleatorio con `+ENABLE_ALEATORIO` (AC4) (US-210).
- `hw/tb/core/tb_core_control.v`: señales de riesgo del flush básico, layout de los buses de latches, ABORT (AC6), núcleo congelado con `o_halted`, `i_flush_all` (no borra bitmap ni DMEM) e `i_reset` (US-210).
- `make sim-programs`: ensambla `asm/tests/h2`, genera el `.expected` con el golden model y corre cada programa con enable fijo y aleatorio; entra en `make check` y en el CI (US-210).
- `make timing-core` (`hw/scripts/timing_core_ooc.tcl`): síntesis e implementación fuera de contexto de `riscv_core` a 100 MHz; deja `hw/reports/timing_core_ooc.rpt` y `util_core_ooc.rpt` (primer dato: WNS = +1,286 ns, WHS = +0,097 ns) (US-210).
- `hw/rtl/core/forwarding_unit.v`: selectores `fwd_a`/`fwd_b` (EX/MEM > MEM/WB > banco); no reenvía desde `x0`, desde burbujas ni desde instrucciones que no escriben el banco. Conectada en `riscv_core` (`o_fwd_a`/`o_fwd_b`) (US-301).
- `hw/tb/core/tb_forwarding_unit.v`: casos dirigidos y 5000 combinaciones aleatorias contra un modelo de referencia (US-301).
- `asm/tests/hazards/`: `fwd_ex_mem`, `fwd_mem_wb`, `fwd_doble`, `fwd_store_data`, `fwd_branch`, `x0_no_forward` y `jal_jalr`, sin `nop` entre instrucciones dependientes; `make sim-programs` también los corre (US-301).
- `hw/rtl/core/hazard_unit.v`: detección de load-use (load válido en EX, `rd ≠ x0`, la instrucción de ID lee ese registro según `uses_rs1`/`uses_rs2`); en `riscv_core` el stall mantiene PC e IF/ID, mete una burbuja en ID/EX y sale por `o_stall` (US-302).
- `hw/tb/core/tb_hazard_unit.v`: casos dirigidos y 5000 combinaciones aleatorias contra un modelo de referencia (US-302).
- `asm/tests/hazards/load_use.asm` y `load_use_store.asm`; `tb_core_control` cuenta los ciclos de stall de cada caso de load-use (US-302).
- `hazard_unit.v` con todo el control de riesgos, como el datapath: elige el próximo PC (`pc_sel`), genera StallF, StallD, FlushD, FlushE y la burbuja de ID/EX con la tabla de prioridades (redirección de EX > ABORT > `jal` > load-use > HALT) y tiene el registro `halt_fetch`; `PC_SEL_*` en `control_defs.vh` (US-303).
- `asm/tests/hazards/`: `branch_taken`, `branch_not_taken`, `branch_after_load`, `jal_branch_same_cycle`, `halt_after_branch`, `halt_speculative` e `illegal_speculative`; `tb_core_control` verifica la penalidad 0 del branch no tomado y ABORT con un branch tomado en EX (US-303).
- `asm/README.md`: convención de la firma (ADR-014): `[0x3FC]` = 1 si todos los casos pasan, el número del caso que falló (desde 2) o 0 si el programa no llegó al final; registros reservados (`x31` caso, `x30` marca de camino equivocado, `x28`/`x29` temporales) y plantilla (US-304).
- `asm/tests/instr/`: un programa por familia (`r_arith`, `r_logic`, `r_shift`, `i_arith`, `i_logic`, `i_shift`, `lui`, `loads`, `stores`, `branches`, `jal`, `jalr`) y `misaligned`, con casos borde y firma; entre todos usan las 33 instrucciones (US-304).
- `asm/demos/`: `suma_arreglo`, `fibonacci`, `copia_cadena`, `burbuja` y `subrutina` (jal/ret con pila) (US-304).
- `asm/special/`: `no_halt`, `infinite_loop` (para ABORT) e `illegal` (US-304).
- `tools/tests/test_asm_suite.py`: ensambla y corre todo `asm/` en el golden model; verifica la firma, el resultado de cada demo y special, que `tests/instr/` cubra las 33 instrucciones y que haya un programa por caso de riesgo (US-304).
- `tools/scripts/verify_rtl.py` y `make verify`: verificación cruzada de todo `asm/` en el núcleo contra el golden model (motivo, PC, registros, memoria usada, firma e instrucciones retiradas); muestra cada diferencia con el valor esperado y el obtenido, imprime la tabla de ciclos, CPI, stalls y flushes y la guarda en `docs/informe/datos/cpi.csv`; termina con código 1 si algún programa falla. `make check` y el CI también la corren (US-305).
- `tb_core_programs`: cuenta ciclos, instrucciones retiradas, stalls y flushes e imprime un volcado final (`VOLCADO <clave> <valor>`) que parsea `verify_rtl.py` (US-305).
- `hw/rtl/core/dmem_bitmap.v`: bitmap de memoria usada y contador (ADR-008), separado de `data_mem`; marca con `o_core_we`/`o_core_addr` de `data_mem` (H2-E2).
- `make synth-ooc` (`hw/scripts/synth_ooc.tcl`): síntesis fuera de contexto de cada módulo de `hw/rtl/core/` con Vivado en modo batch; deja en `build/synth/` el reporte de utilización de cada módulo y una tabla con LUTs, LUTRAM, FF, latches, BRAM y *critical warnings*, y falla si algún módulo infiere latches (H2-E1).
- `hw/rtl/debug/`: Debug Unit completa (`debug_unit` con `du_cmd_fsm`, `du_loader`, `du_exec_ctrl`, `du_dumper`, `du_resp_tx` y `du_tx_mux`): intérprete de comandos con checksum y NACK, carga y reprogramación de la IMEM, modos `RUN`/`STEP`, `ABORT` con drenado del pipeline, snapshot y `DUMP_MEM` según `docs/protocolo.md` (US-403 a US-408).
- `hw/tb/common/uart_host_model.vh` (modelo de la UART de la PC para los testbenches), `hw/tb/debug/core_stub.v` (núcleo falso sintetizable) y un testbench por módulo de la Debug Unit (`tb_du_*`, `tb_core_stub`, `tb_uart_host_model`) (US-402 a US-408).
- `hw/scripts/synth_du_ooc.tcl` y `hw/constraints/du_ooc.xdc`: síntesis e implementación de la Debug Unit fuera de contexto a 100 MHz, con los reportes `hw/reports/du_ooc_*.rpt` (US-408).
- `tools/riscv_toolkit/protocol/`: `codec` (armado y lectura de tramas), `snapshot` (decodifica el snapshot de 221 + 6·K bytes), `Transport` con `SerialTransport` (pyserial) y `FakeTransport` (la Debug Unit simulada en Python sobre el golden model) (US-409).
- `tools/riscv_toolkit/session/`: `DebugSession` (conexión, carga, ejecución y volcados con timeouts y reintentos), `SnapshotHistory` y `diff` entre snapshots (US-410).
- CLI `rvdbg` como subcomando `dbg` de `python -m riscv_toolkit` (`cli/rvdbg.py`) para manejar la placa desde la terminal (US-410).
- `tools/scripts/verify_board.py` (toda la suite de `asm/` en la placa contra el golden model) y `tools/scripts/uart_echo_test.py` (US-401, US-411).
- `docs/guias/guia-riscv-toolkit.md`, `docs/guias/guia-reporte-timing.md` y `docs/guias/guia-caso-timing-debug-unit.md` (H4).
- Interfaz gráfica (`tools/riscv_toolkit/ui/`, Flet): pantalla de conexión, editor con ensamblado y errores por línea, controles de ejecución, registros, memoria, vista del pipeline con los latches campo a campo, carta de pipeline, línea de tiempo con historial navegable, resumen y verificación contra el golden model (US-501 a US-505).
- `session/export.py` (exportar y abrir sesiones guardadas en JSON) y `session/verificar.py` (comparación de un snapshot con el golden model) (US-505).
- `asm/demos/` `factorial` y `hola`, `asm/errores/` (un programa por error del ensamblador, para la GUI) y `asm/special/ilegal` (H5).
- `docs/manual/checklist_ui.md`: prueba manual de la interfaz pantalla por pantalla (H5).

### Changed

- ADR-016 aprobado: 85 MHz con Clock Wizard (WNS = +0,345 ns, WHS = +0,054 ns); falta la suite en placa (US-602).
- `basys3.xdc`: `create_clock` sin `-add`, para que el reloj de la placa reemplace al que crea el `.xdc` del Clock Wizard en el mismo pin (con `-add` quedaban dos relojes primarios iguales y Vivado analizaba caminos entre ellos) (US-602).
- `du_loader`: parámetro `RELLENO_HALT` (1 por defecto); en 0 no rellena con HALT el resto de la IMEM, solo para el experimento de `tb_top_sin_halt` (US-604).
- `tb_core_control`: perro guardián de 20000 ciclos y límite en la espera del `addi` del lazo; con un error en la hazard unit el testbench falla en vez de quedar colgado (en el CI lo cortaría recién el límite de 6 h de GitHub Actions) (US-305).
- Los programas de `asm/tests/hazards/` se verifican solos con la firma en `0x3FC`; las marcas de camino equivocado pasan a `x30` y `halt_speculative` sale del lazo con un `beq`, así el `halt` que sigue al `bne` siempre es especulativo. `make sim-programs` también corre `asm/tests/instr/` (US-304).
- `if_stage`: el próximo PC lo elige `pc_sel` (hazard unit) y el PC se frena con `i_stall_f`; la prioridad entre redirecciones y el registro `halt_fetch` pasan de `if_stage`/`riscv_core` a `hazard_unit`. `tb_if_stage` maneja esas señales a mano y las prioridades se prueban en `tb_hazard_unit` (US-303).
- Timing del núcleo fuera de contexto a 100 MHz: WNS = +0,119 ns (antes +1,286 ns); camino crítico forwarding → `branch_cmp` → redirección → flush de IF/ID (US-303).
- `hw/scripts/sim.sh` y `make sim`: aceptan `EXPECTED=<ruta>` (`+EXPECTED`) y `ARGS="..."` (plusargs extra); `make sim-all` ya no corre `tb_core_programs`, que necesita un programa (US-210).
- CI: el job de HDL instala `uv` y corre `make sim-programs` (US-210).
- `data_mem.v`: el bitmap y el contador pasan a `dmem_bitmap.v`; `data_mem` saca la marca del store efectivo (`o_core_we`, `o_core_addr`) y pierde `i_clear_used`, `o_dbg_used` y `o_used_count`. Mismo comportamiento: `tb_data_mem` prueba los dos módulos conectados (H2-E2).
- `python -m riscv_toolkit` usa argparse y despacha subcomandos; sin subcomando sigue mostrando la versión, y se agregó `--version` (US-107).
- `identificar(palabra)` pasa del desensamblador a `isa/instrucciones.py` para que el golden model reconozca las mismas instrucciones legales (US-108).
- Módulos UART: correcciones para dejar el lint en cero, sin cambio de comportamiento (constantes con el ancho de los contadores, `default` en las máquinas de estado, señal sin usar eliminada en `baudrate_gen`) (US-102).
- `mypy` también revisa `tools/scripts/` (US-104).
- `baudrate_gen`: el ancho del contador se deriva de `COUNT_MAX` con `$clog2` (se quita el parámetro `BITS`); el top calcula `COUNT_MAX` redondeando `CLK_FREQ_HZ / (16·BAUD)` (ADR-002) (US-401).
- `hw/constraints/basys3.xdc` pasa a los puertos de `top.v` (`o_led[3:0]`) y declara `set_false_path -from [get_ports rx]` (US-401).
- `tb_top_echo.v` usa `uart_host_model.vh` en lugar de sus propias tareas de envío y recepción (US-402).
- `make lint` también revisa `hw/tb/debug/core_stub.v`, que tiene que seguir siendo sintetizable (US-402).
- `HALT_OPCODE` y `HALT_WORD` pasan de `protocol/comandos.py` a `isa/instrucciones.py`; `gen_du_defs.py` los toma de ahí y `du_defs.vh` no cambia (US-105).
- ADR-013: los registros se escriben solo como `x0`–`x31`; los nombres ABI pasan al roadmap. Actualizados PRD (US-105, US-106, US-303, US-504, §13, §14, §15), ADR-012 y guía del datapath (US-105).
- `make setup` también instala `binutils-riscv64-unknown-elf` (solo para `make gnu-ref`) (US-106).
- `debug_unit` instancia `du_loader`: se quitan los puertos `o_req_load`/`o_load_*`/`i_load_*`/`o_req_reset`/`i_reset_done` y se agregan los del núcleo (`o_imem_*`, `o_dmem_*`, `o_clear_used`, `o_flush_all`) y `o_load_done`, más los parámetros `IMEM_ADDR_BITS`/`DMEM_ADDR_BITS` (US-404).
- `tb_du_cmd_fsm.v` usa el `du_loader` real con un `core_stub` en lugar del loader falso; además verifica la palabra cargada en la IMEM y el HALT después de un `LOAD` cortado (US-404).
- `debug_unit` instancia `du_exec_ctrl`: se quitan `o_req_run`/`o_req_step`/`o_req_abort`/`i_step_done`/`i_run_fin` y `o_load_done` (ahora interno), y se agregan `o_enable`, `o_stop_fetch` y `o_ciclos` (hasta que entre `du_dumper`) (US-406).
- `tb_du_cmd_fsm.v` usa el `du_exec_ctrl` real moviendo el `core_stub`; el fin del drenado de `ABORT` se emula levantando `i_halted` hasta US-407 (US-406).
- `debug_unit` recibe `i_latch_valid[3:0]` (bits `valid` de los latches, hasta que entren los buses para `du_dumper`) y `tb_du_cmd_fsm.v` drena de verdad con los `valid` del `core_stub`, sin la emulación de `ABORT` (US-407).
- `du_dumper` calcula la longitud y la posición del checksum una sola vez al pedido (`r_len`, `r_pos_checksum`) en lugar de en cada ciclo: salen del camino crítico (`r_k` → sumas → comparación → `r_xor`, WNS 0,859 ns en la primera síntesis OOC).
- `debug_unit` instancia `du_dumper` (canal 1 del mux, `i_ciclos` desde `du_exec_ctrl`): se quitan los puertos del dumper externo, `o_ciclos` e `i_latch_valid` (los `valid` salen de los buses) y se agregan los puertos de lectura del núcleo (PC, registros, DMEM, bitmap, riesgos y latches). `tb_du_cmd_fsm.v` usa el dumper real en lugar del falso (US-405, US-408).
- PRD US-106: `ensamblar` es una función en vez de la clase `Assembler`, la `Imagen` suma `expansiones` y el fixture de GNU pasa a `tools/tests/assembler/fixtures/` (también en ADR-013) (US-106).

### Removed

- `hw/tb/uart/tb_top_echo.v`: el `top` ya no es el eco de la UART; lo reemplaza `tb_top_system` (US-411).
- `TP3/clockInfo.txt` y `TP3/dfx_runtime.txt`: archivos sueltos de Vivado versionados por error; `make` ahora corre Vivado dentro de `build/`.

[Unreleased]: https://github.com/nicopinera/tps-arqui/commits/develop
