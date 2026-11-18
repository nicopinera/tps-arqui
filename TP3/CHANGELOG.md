# Changelog

Todos los cambios relevantes del TP3 se registran en este archivo.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen el esquema de la sección 15 del PRD.

## [Unreleased]

### Added

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
- `hw/rtl/top.v`: top del TP3 con parámetros `CLK_FREQ_HZ` y `BAUD`, sincronizador de `rx` con `ASYNC_REG`, eco temporal RX → TX y LED3 de error de paridad (LED0–2 quedan para la Debug Unit) (US-401).
- `uart_rx` valida la paridad par: un byte con paridad errónea no levanta `o_rx_done` y levanta `o_parity_err` (ADR-002) (US-401).
- `hw/tb/uart/tb_top_echo.v` y casos nuevos en `tb_uart_loopback.v`: tramas con paridad errónea, período real del tick y error de baud < 2 % (US-401).
- `tools/scripts/uart_echo_test.py`: prueba de eco en placa con bytes aleatorios a 19200 bps 8E1; dependencia `pyserial` (US-401).
- `hw/tb/debug/core_stub.v`: núcleo falso sintetizable con los mismos puertos que `riscv_core` (v0.1): contador de ciclos con enable, IMEM escribible, DMEM con bitmap y contador, drenado con `i_stop_fetch`, `i_flush_all` y terminación programable (`HALT_AFTER`, `ILLEGAL`) (US-402).
- `hw/tb/common/uart_host_model.vh`: modelo de la PC para testbenches (`send_byte`, `send_byte_paridad`, `recv_byte`, `send_cmd` con paridad mala o trama truncada, `recv_frame` con validación de checksum) (US-402).
- `tb_uart_host_model.v` y `tb_core_stub.v` (US-402).
- `hw/rtl/debug/du_cmd_fsm.v`: intérprete de comandos de la Debug Unit con la tabla de comandos por estado (R-DU-1), las transiciones de `docs/protocolo.md` §5, `NACK(ERR_DESCONOCIDO)`/`NACK(ERR_ESTADO)`, error de paridad (R-DU-5), timeout de recepción parametrizable (R-DU-6) y drenado antes de responder errores en medio de los argumentos (§7.2). Despacha a los submódulos por pulsos `o_req_*` y respuestas `i_*_done` (US-403).
- `hw/rtl/debug/du_resp_tx.v`: serializador de las respuestas cortas `ACK`, `NACK(código)` y `PING_INFO` con checksum (US-403).
- `hw/rtl/debug/du_tx_mux.v`: multiplexor de `uart_tx` entre las respuestas cortas y el futuro `du_dumper`, con el `o_tx_done` dirigido solo al canal elegido (US-403).
- `hw/rtl/debug/debug_unit.v`: wrapper que conecta los tres módulos y expone los puertos de `du_loader`, `du_exec_ctrl` y `du_dumper` hasta sus historias (US-403).
- `tb_du_tx_mux.v`, `tb_du_resp_tx.v` (las 9 tramas fijas de §8.1) y `tb_du_cmd_fsm.v` (la Debug Unit por la UART con submódulos emulados; AC1 a AC6) (US-403).
- `hw/rtl/debug/du_loader.v`: recibe `N` y las palabras de `LOAD` (little-endian), las escribe en la IMEM y verifica el checksum XOR. Al terminar recorre las 256 direcciones: HALT en la IMEM desde `N` (o en toda, con error o cancelación) y 0 en la DMEM; después pulsa `flush_all`, `clear_used` y `load_done`. `RESET` hace la misma limpieza sin tocar la IMEM (ADR-009, R-DU-4) (US-404).
- `hw/tb/debug/tb_du_loader.v`: carga válida, `N = 256`, checksum incorrecto, cancelación en medio de la carga y durante la limpieza, `ERR_TAMANO` con `N = 0` y `N > 256`, `RESET` y cinco cargas seguidas, contra `core_stub` (AC3, AC5, AC7) (US-404).
- `docs/guias/guia-estudio-debug-unit.md`: Parte 3 sobre `du_loader` (estados, registros, ejemplo ciclo a ciclo, errores comunes) (US-404).
- `hw/rtl/debug/du_exec_ctrl.v`: modos `RUN` (enable sostenido hasta `o_halted`, fin como nivel `o_run_fin`) y `STEP` (un solo ciclo de enable, `o_step_done` un ciclo después); `i_enable` sale de un flip-flop (ADR-001, R-EJ-1, R-EJ-2) y contador de ciclos de 32 bits que solo suma cuando el núcleo avanza y vuelve a 0 con `load_done`. `ABORT` (`i_stop_fetch`) queda para US-407 (US-406).
- `hw/tb/debug/tb_du_exec_ctrl.v`: con dos `core_stub` (fin por HALT y por ilegal) verifica un ciclo por STEP, STEP repetido = RUN (R-EJ-7), `o_run_fin` como nivel y la terminación por ilegal en ambos modos (AC1, AC2, AC6) (US-406).
- `docs/guias/guia-estudio-debug-unit.md`: Parte 5 sobre `du_exec_ctrl` (estados, ejemplo ciclo a ciclo, contador, errores comunes) (US-406).
- `du_exec_ctrl.v`: `ABORT` con estado `DRAIN`: `o_stop_fetch = 1` con el enable en 1 hasta que los 4 `valid` de los latches (`i_valid`) valen 0, o hasta `i_halted` si un HALT llega a WB durante el drenado; después `o_run_fin` como un RUN (ADR-010) (US-407).
- `hw/tb/debug/tb_du_abort.v`: loop infinito + `ABORT` (drenado en 3 ciclos, latches vacíos, PC congelado), HALT durante el drenado, `ABORT` junto con `i_halted` y `ABORT` en `IDLE` (AC1) (US-407).
- `docs/guias/guia-estudio-debug-unit.md`: §47 sobre el drenado de `ABORT` (US-407).
- `du_dumper.v`: trama `MEM_DATA` de `DUMP_MEM` (`A5 05 len | dir | n | n palabras | XOR`) con el mismo serializador del snapshot (registro `r_modo`); valida el rango en 17 bits (alineada, `n ≥ 1`, `dir/4 + n ≤ 256`) y, si está mal, termina sin mandar nada con `o_err = ERR_RANGO` (US-408).
- `hw/tb/debug/tb_du_dump_mem.v`: `DUMP_MEM` de punta a punta por la UART con `core_stub`: las palabras coinciden con la DMEM, rangos inválidos → `NACK(ERR_RANGO)` sin cambio de estado, `NACK(ERR_ESTADO)` en `RUN` y los ejemplos de `protocolo.md` §8.9 byte a byte (AC1–AC4) (US-408).
- `tb_du_dumper.v`: casos de `MEM_DATA` (bordes, DMEM entera, ejemplo §8.9) y de rechazo (no alineada, `n = 0`, se pasa del final, desborde con `n = FFFF`) (US-408).
- `docs/guias/guia-estudio-debug-unit.md`: §37 sobre la trama `MEM_DATA` (US-408).
- `docs/guias/guia-caso-timing-debug-unit.md`: caso de estudio de la síntesis OOC de la DU (primer reporte, camino crítico por la longitud recalculada, el cambio a `r_len`/`r_pos_checksum`, antes y después: WNS 0,859 → 1,873 ns, 12 → 7 niveles de lógica).
- `hw/scripts/synth_du_ooc.tcl` y `hw/constraints/du_ooc.xdc`: síntesis e implementación _out-of-context_ de `debug_unit` a 100 MHz en la xc7a35t, con reportes de utilización y timing en `hw/reports/du_ooc_*.rpt` (ADR-016).
- `docs/guias/guia-riscv-toolkit.md`: mapa del software de PC (`isa`, `assembler`, `disasm`, `iss`, `protocol/comandos.py`, `cli`, `scripts`), cómo se conectan y cómo se prueban.
- `tools/riscv_toolkit/protocol/codec.py`: `encode_cmd`, `encode_load`, `encode_dump_mem`, `encode_trama` y `checksum` (XOR); `FrameReader` arma tramas de bytes en pedazos y valida `A5`, tipo, longitud por tipo y checksum, con excepciones específicas (`ErrorChecksum`, `ErrorLongitud`, `ErrorTipo`, `ErrorTramaTruncada`, `ErrorPayload`) que descartan la trama y dejan seguir con la siguiente (US-409, AC1, AC3).
- `protocol/snapshot.py`: `Snapshot`, `LatchIFID`, `LatchIDEX`, `LatchEXMEM`, `LatchMEMWB`, `RiesgosCiclo` y `MemRange` (`@dataclass(frozen=True)`), con `from_bytes` y `to_bytes` según ADR-017 (US-409, AC2).
- `protocol/transport.py` (interfaz `Transport` como `typing.Protocol`), `serial_transport.py` (`pyserial` a 19200 8E1, detección de la Basys 3 por VID/PID `0403:6010`) y `fake_transport.py` (la Debug Unit respondida por el golden model, con las reglas de R-DU-1 y `simulado = True`) (US-409, AC4–AC6).
- `tests/protocol/`: `test_codec.py`, `test_snapshot.py` (ejemplos §8.5 y §8.7, y la captura real `fixtures/snapshot_sim.bin`), `test_fake_transport.py` (RUN igual al golden model en los programas de `tests/iss/fixtures` y con `ILLEGAL`) y `test_serial_transport.py` (configuración del puerto con `serial` falso; solo `serial_transport.py` importa `serial`) (US-409).
- `tb_du_cmd_fsm.v` guarda el payload del snapshot de `RUN → ILLEGAL` en `build/snapshot_sim.bin` (K = 256, 1757 B); la copia versionada está en `tools/tests/protocol/fixtures/` (US-409, AC2).
- `tools/riscv_toolkit/session/debug_session.py`: `DebugSession(transport, timeouts)` con `conectar` (PING con 3 reintentos y chequeo de `PROTO_VERSION`), `ping`, `load`, `reset`, `step`, `dump`, `dump_mem`, `run` y `abort`; `NACK` como `ErrorNackDU` con mensaje legible que nombra el estado (lo averigua con un `DUMP` si hace falta), `ErrorRespuesta`, `ErrorVersion`; timeouts del protocolo §7.4 (`Timeouts`) y espera de `RUN` sin límite en lecturas cortas para que Ctrl+C la corte; ignora `NACK(PARIDAD)` durante `RUN`, descarta el `NACK` de un `ABORT` que llegó tarde, y no manda `LOAD`/`DUMP_MEM` a una DU en `RUN` (US-410, AC2, AC3).
- `session/history.py` (`SnapshotHistory`: snapshots de la sesión con cursor) y `session/diff.py` (`diff(a, b) -> CambiosEstado` con PC, registros y memoria que cambiaron) (US-410).
- CLI `rvdbg` como subcomando `dbg` (`cli/rvdbg.py`): acciones `ping`, `load`, `run`, `step [N]`, `dump`, `dump-mem`, `reset`, `abort` y `shell` (modo interactivo con la misma sesión); opciones `--port`, `--fake` y `--json`; `run` y `step` aceptan `--load`; Ctrl+C durante `run` manda `ABORT` (US-410, AC1–AC5).
- `asm/demos/fibonacci.asm` y `asm/special/infinite_loop.asm` (US-410).
- `tests/session/` (`test_debug_session.py` con `FakeTransport` y con transportes que inyectan errores, `test_history.py`, `test_diff.py`) y `tests/cli/test_rvdbg.py` (US-410).
- `tools/scripts/verify_board.py`: por cada programa, LOAD → RUN → compara registros, memoria usada y motivo contra el golden model; `--step` corre todo con STEP y lo compara con RUN; carga los programas seguidos sin RESET; reporte Markdown con commit y SHA-256 del bitstream (`--reporte`, `--bitstream`); `--fake` para correrlo sin placa. Probado con `tests/scripts/test_verify_board.py` (US-411, AC1–AC4; falta la corrida en placa).

### Changed

- `FakeTransport.read` duerme el `timeout` pedido cuando no hay nada para leer, como una placa que no contesta, para que la espera de `RUN` no gire en vacío (US-410).
- `rvsim`: `volcado(regs, mem_usada)` pasa a ser público y lo usa también `rvdbg` (US-410).
- `docs/guias/guia-riscv-toolkit.md`: secciones de `session/`, la CLI `dbg` y `verify_board.py` (US-410, US-411).
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
