# Changelog

Todos los cambios relevantes del TP3 se registran en este archivo.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen el esquema de la sección 15 del PRD.

## [Unreleased]

## [1.2.1] - 2026-11-21

Esta versión no cambia el hardware ni el software, solo la documentación. Agrega un README principal al repositorio, que presenta los tres TPs y explica cómo usarlos, y reescribe este CHANGELOG para que cuente qué se hizo en el TP3 en lugar de listar archivos. También se completan las guías de estudio del datapath y de los bloques del núcleo.

### Qué se hizo en el TP3

El objetivo del TP3 fue implementar en la Basys 3 un **procesador RISC-V de 32 bits (RV32I) segmentado en 5 etapas**, que se pudiera programar y observar desde una PC por la UART del TP2. El trabajo se planificó en un PRD con seis hitos, y cada decisión que el enunciado dejaba abierta se registró en un ADR (hay 20 en `docs/adr/`). A partir del segundo hito, el trabajo se dividió en dos pistas paralelas: una armó el núcleo y la otra, la Debug Unit y el software de PC. Cada pista trabajó contra una versión simulada de la otra, con las interfaces fijadas desde el principio, y las dos se juntaron al final en la placa.

**El núcleo** (`hw/rtl/core/`) tiene las cinco etapas clásicas (IF, ID, EX, MEM y WB) separadas por cuatro latches, y ejecuta las 32 instrucciones que pide el enunciado más una instrucción `HALT` propia. Primero se lo hizo andar con un flush básico en los saltos y programas que evitaban las dependencias a mano. Después se agregó el manejo completo de riesgos. Una **forwarding unit** reenvía resultados desde EX/MEM y MEM/WB a la entrada de la ALU, y una **hazard unit** concentra el resto del control: frena un ciclo el pipeline en el caso load-use, descarta las instrucciones del camino equivocado cuando hay un salto (los `jal` se resuelven en ID y los branches y `jalr` en EX, con predicción _not-taken_), detiene la búsqueda ante un `HALT` o una instrucción ilegal y resuelve las prioridades cuando varios eventos coinciden. La ALU es nueva, de 32 bits y con un código interno de operación, porque la del TP1 no se adaptaba a la codificación de RISC-V (ADR-019).

**La Debug Unit** (`hw/rtl/debug/`) recibe comandos de la PC por la UART. Puede cargar un programa nuevo en la memoria de instrucciones sin resintetizar, ejecutarlo de corrido o de a un ciclo, abortarlo y devolver un snapshot con los 32 registros, el contenido de los 4 latches, la memoria de datos que se usó y las señales de riesgo del ciclo. El reloj no se toca en ningún momento: el avance del núcleo se controla con un _clock enable_, así que todo el sistema queda en un único dominio de reloj. El protocolo está documentado byte a byte en `docs/protocolo.md`.

**El software de PC** (`tools/riscv_toolkit/`) se escribió en Python 3.13. Incluye un ensamblador propio de dos pasadas, un desensamblador, un _golden model_ que ejecuta los programas sin pipeline, un modelo del pipeline ciclo a ciclo, una CLI (`asm`, `sim`, `dbg`) y una interfaz gráfica en Flet. La GUI muestra los registros, la memoria, los latches campo a campo, la carta de pipeline y el datapath animado con el valor de cada cable. Todo sale de una única tabla de instrucciones, de la que también se genera un archivo de definiciones del hardware.

**La verificación** se hizo en capas. Cada módulo tiene un testbench que se verifica solo. Los programas de `asm/tests/` dejan una firma en memoria que indica qué caso falló, y se corren en el núcleo con el enable fijo y aleatorio. Además, todo el directorio `asm/` se compara contra el golden model, y la suite completa se pasa por la UART simulada al `top`. Para confirmar que las pruebas detectan errores de verdad, se introdujeron mutaciones a propósito, y todas se detectaron. GitHub Actions corre todo esto en cada push.

**En la implementación** el diseño no cerró timing a 100 MHz. Lo inesperado fue que el camino crítico no estaba en el pipeline sino en la Debug Unit, armando el snapshot a partir de la memoria de datos, y no se veía sintetizando los módulos por separado. En lugar de adivinar una frecuencia, se hizo un barrido y se eligió la mayor que dejaba al menos 0,3 ns de margen: **85 MHz**, generados con un Clock Wizard (WNS = +0,345 ns). El diseño ocupa menos del 20 % de la FPGA y logra un CPI de entre 1,23 y 1,44 en los programas de demostración. Casi toda la pérdida respecto del CPI ideal viene de los saltos.

El informe completo es `TP3/README.md`. Su respaldo (timing, métricas y datos) está en `docs/informe/`, y el manual de usuario y la hoja de referencia de la ISA, en `docs/manual/`.

## [1.2] - 2026-11-21

Versión final del TP3 en cuanto a contenido. `TP3/README.md` pasó a ser el informe final, con el mismo formato que el del TP2, y se sumaron el gráfico de WNS según la frecuencia y el Clock Wizard en el diagrama de arquitectura. Las notas de esta versión listaban los archivos por grupo; la [1.2.1] cuenta lo mismo de forma narrativa.

## [1.1] - 2026-11-20

Se ajustó el formato de este CHANGELOG para que el workflow de release (`.github/workflows/release.yml`) pueda armar las notas a partir de la sección de cada versión.

## [1.0] - 2026-11-20

Primera versión completa, con los seis hitos del PRD integrados en `main`: núcleo, riesgos, Debug Unit, interfaz gráfica, timing e informe.

[Unreleased]: https://github.com/nicopinera/tps-arqui/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/nicopinera/tps-arqui/compare/v1.2...v1.2.1
[1.2]: https://github.com/nicopinera/tps-arqui/compare/v1.1...v1.2
[1.1]: https://github.com/nicopinera/tps-arqui/compare/v1.0...v1.1
[1.0]: https://github.com/nicopinera/tps-arqui/releases/tag/v1.0
