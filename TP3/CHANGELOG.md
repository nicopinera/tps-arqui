# Changelog

Todos los cambios relevantes del TP3 se registran en este archivo.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen el esquema de la sección 15 del PRD.

## [Unreleased]

## [1.2] - 2026-11-21

Versión final del TP3: procesador RISC-V (RV32I) segmentado en 5 etapas sobre la Basys 3, con una Debug Unit que lo programa, ejecuta y vuelca por UART, y software de PC para manejarlo. El informe es `TP3/README.md`.

### Added

- **Núcleo RV32I** (`hw/rtl/core/`): las 5 etapas (`if_stage`, `id_stage`, `ex_stage`, `mem_stage`, `wb_stage`), los 4 latches (`if_id_reg`, `id_ex_reg`, `ex_mem_reg`, `mem_wb_reg`), los bloques funcionales (`alu`, `alu_control`, `branch_cmp`, `reg_file`, `control_unit`, `imm_gen`, `instr_mem`, `data_mem`, `dmem_bitmap`, `store_align`, `load_extend`), la `forwarding_unit`, la `hazard_unit` y `riscv_core`, que los integra. Ejecuta las 32 instrucciones del enunciado más `halt`, con forwarding, stall por load-use y predicción _not-taken_.
- **Debug Unit** (`hw/rtl/debug/`): `debug_unit` con sus submódulos `du_cmd_fsm` (intérprete de comandos), `du_loader` (carga y reprogramación), `du_exec_ctrl` (`RUN`, `STEP`, `ABORT`), `du_dumper` (snapshot y `DUMP_MEM`), `du_resp_tx` y `du_tx_mux` (respuestas). Implementa el protocolo de `docs/protocolo.md`.
- **Sistema en la placa**: `hw/rtl/top.v` (UART + Debug Unit + núcleo, LEDs de estado), el Clock Wizard `hw/ip/clk_wiz_0/` que genera los 85 MHz y las restricciones `hw/constraints/basys3.xdc`. La UART del TP2 (`hw/rtl/uart/`) ahora valida la paridad.
- **Testbenches** (`hw/tb/`): uno por módulo del núcleo (`tb_alu`, `tb_reg_file`, `tb_if_stage`, `tb_hazard_unit`, …) y de la Debug Unit (`tb_du_*`), y los de integración `tb_core_programs`, `tb_core_control`, `tb_top_system` y `tb_top_sin_halt`, más los modelos `core_stub` y `uart_host_model`.
- **Programas en ensamblador** (`asm/`): pruebas con firma en `tests/` (por instrucción, por caso de riesgo y del Hito 2), demos en `demos/` (`fibonacci`, `burbuja`, `factorial`, `subrutina`, …), casos cortos para mirar en la GUI en `riesgos/`, casos especiales en `special/` (sin `halt`, lazo infinito, ilegal) y ejemplos de errores del ensamblador en `errores/`.
- **Software de PC** (`tools/riscv_toolkit/`): ensamblador (`assembler/`), desensamblador (`disasm/`), tabla de la ISA (`isa/`), golden model y modelo del pipeline (`iss/`), codec del protocolo y transporte serie o simulado (`protocol/`), sesión con historial (`session/`), CLI `asm`, `sim` y `dbg` (`cli/`) e interfaz gráfica en Flet con vista del datapath (`ui/`).
- **Scripts y automatización**: objetivos del `Makefile` (`lint`, `sim-all`, `sim-programs`, `verify`, `sim-system`, `impl`, `freq-sweep`, `grafico-wns`, `reportes`, `check`, …), scripts de Vivado en `hw/scripts/`, scripts de Python en `tools/scripts/` (`verify_rtl`, `verify_board`, `resumen_reportes`, `grafico_wns`, generadores de `du_defs.vh` y de vectores) y los workflows de CI y de release en `.github/workflows/`.
- **Reportes de Vivado** (`hw/reports/`): timing, utilización, potencia y DRC del diseño final a 85 MHz, el "antes" a 100 MHz y el barrido de frecuencias.
- **Documentación**: el informe final (`TP3/README.md`), con su respaldo en `docs/informe/` (timing, métricas y datos), el PRD, los 20 ADR, los contratos de `docs/interfaces/`, el protocolo, los diagramas, las guías de estudio de `docs/guias/`, el manual de usuario, la hoja de referencia de la ISA y el guion de la defensa.

### Changed

- `TP3/README.md` pasa a ser el informe final, con el mismo formato que el del TP2.
- Este CHANGELOG se reorganizó por grupo de archivos, para que las notas del release se puedan leer.

## [1.1] - 2026-11-20

### Changed

- Sección de la versión en este CHANGELOG, para que el workflow de release (`.github/workflows/release.yml`) arme las notas a partir de ella.

## [1.0] - 2026-11-20

Primera versión completa: los 6 hitos del PRD (núcleo, riesgos, Debug Unit, GUI, timing e informe) integrados en `main`. El detalle de lo que incluye está en la versión [1.2].

[Unreleased]: https://github.com/nicopinera/tps-arqui/compare/v1.2...HEAD
[1.2]: https://github.com/nicopinera/tps-arqui/compare/v1.1...v1.2
[1.1]: https://github.com/nicopinera/tps-arqui/compare/v1.0...v1.1
[1.0]: https://github.com/nicopinera/tps-arqui/releases/tag/v1.0
