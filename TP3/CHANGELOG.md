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

### Changed

- Módulos UART: correcciones para dejar el lint en cero, sin cambio de comportamiento (constantes con el ancho de los contadores, `default` en las máquinas de estado, señal sin usar eliminada en `baudrate_gen`) (US-102).
- `mypy` también revisa `tools/scripts/` (US-104).
- `HALT_OPCODE` y `HALT_WORD` pasan de `protocol/comandos.py` a `isa/instrucciones.py`; `gen_du_defs.py` los toma de ahí y `du_defs.vh` no cambia (US-105).
- ADR-013: los registros se escriben solo como `x0`–`x31`; los nombres ABI pasan al roadmap. Actualizados PRD (US-105, US-106, US-303, US-504, §13, §14, §15), ADR-012 y guía del datapath (US-105).
