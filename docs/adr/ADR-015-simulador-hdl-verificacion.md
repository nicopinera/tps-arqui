# ADR-015 — Simulador HDL y framework de verificación

- **Estado:** Aprobado (revisado el 2026-10-11: Icarus pasa a ser el simulador del proyecto y se agrega el lint con Verilator)
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-102
- **Relacionados:** ADR-005 (memoria inferida, sin IP), ADR-011 (Python), ADR-014 (golden model), ADR-016 (Clock Wizard), ADR-020 (versión de Vivado)

## Contexto

El proyecto necesita simular muchos módulos (ALU, banco de registros, unidades de riesgo, núcleo completo, Debug Unit) y, sobre todo, correr la suite de programas de prueba contra el RTL de forma repetible. US-102 pide un `make sim TB=…` que diga `PASS`/`FAIL` sin mirar formas de onda, y un `make sim-all` que resuma todo.

Hay tres opciones de simulador con perfiles distintos: el que viene con Vivado (alineado con la síntesis), uno libre y liviano (scriptable e instalable en CI) y un framework en Python (que reutiliza el golden model).

**Motivo de la revisión.** La primera versión de este ADR elegía xsim como referencia e Icarus solo para el CI. Al empezar la US-102 se vio que eso obligaba a mantener dos flujos (`sim.tcl` para xsim y otro para Icarus) y a abrir o invocar Vivado para el trabajo diario, que es justamente lo que se quiere evitar. El equipo prefiere un único flujo de terminal, igual en cada máquina y en el CI.

## Decisión

### Lint

- **Verilator** en modo `--lint-only -Wall` sobre todo el RTL sintetizable (`hw/rtl/`, salvo `legacy/`).
- El lint es **obligatorio**: `make lint` falla con cualquier advertencia, y corre en el CI.
- Las excepciones justificadas se silencian en el lugar puntual con `// verilator lint_off NOMBRE` y un comentario con el motivo; no se desactivan advertencias de forma global.

### Simulador

- **Icarus Verilog es el simulador del proyecto**, tanto en las máquinas del equipo como en el CI (`make sim`, `make sim-all`).
- **Los testbenches se escriben en Verilog-2001 estándar**, sin características de SystemVerilog ni primitivas exclusivas de Xilinx.
- Los testbenches son autoverificables: usan `hw/tb/common/tb_utils.vh` (`check_eq`, `tb_finish`) e imprimen `TEST PASSED` o `TEST FAILED (N errores)`.
- `make sim-all` descubre todos los `hw/tb/**/tb_*.v`: agregar un testbench es crear el archivo.
- Los programas se cargan en la IMEM con `$readmemh` a partir del `.hex` del ensamblador (ADR-013); la ruta se pasa con `+HEX=<ruta>`.
- Las ondas se generan solo bajo demanda (`WAVES=1`), en formato `.vcd`.
- **xsim no se automatiza.** Se usa a mano, desde la GUI de Vivado, solo para lo que Icarus no puede simular: el `top` con IP de Xilinx (Clock Wizard, ADR-016) y las simulaciones post-síntesis o post-implementación.

### Integración continua (GitHub Actions)

En cada push y PR:

1. **HDL:** se instalan Verilator e Icarus y se corren `make lint` y `make sim-all`.
2. **Python:** `uv sync` y luego `ruff check`, `ruff format --check`, `mypy`, `pytest` con cobertura (NFR-10) y `pip-audit` sobre `tools/`.

## Alternativas consideradas

| Opción                                               | Ventajas                                                                                              | Desventajas                                                                                    |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| (a) xsim como referencia + Icarus solo en CI         | Mismo entorno que la síntesis; simula IP de Xilinx                                                    | Dos flujos que mantener; xsim es lento para arrancar y obliga a tener Vivado en el PATH        |
| **(b) Icarus como único simulador automatizado** (elegida) | Rápido, liviano y scriptable; el mismo comando en cada máquina y en el CI; no requiere Vivado para el día a día | No simula IP de Xilinx; puede diferir de Vivado en detalles de Verilog                         |
| (c) cocotb (testbenches en Python)                   | Reutiliza el golden model directamente; tests muy expresivos                                          | Otra herramienta que aprender; requiere un simulador por debajo                                |

**Lint**

| Opción                                  | Ventajas                                                                    | Desventajas                                                        |
| --------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| **Verilator obligatorio** (elegida)     | Detecta anchos que no coinciden, latches y señales sin usar antes de simular | Los módulos migrados del TP2 pueden requerir correcciones iniciales |
| Verilator informativo                   | Sin fricción                                                                | Las advertencias se acumulan y se terminan ignorando               |
| Solo las advertencias de la síntesis    | Nada que instalar                                                           | Aparecen tarde, mezcladas con cientos de mensajes de Vivado         |

**CI**

| Opción                                  | Ventajas                                                                                      | Desventajas                                                          |
| --------------------------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| **HDL + Python** (elegida)              | Detecta regresiones de hardware y de software en cada PR, sin depender de la máquina de nadie | Mantener el workflow                                                 |
| Solo Python                             | Workflow trivial                                                                              | Las regresiones de RTL solo aparecen si alguien corre `make sim-all` |
| Sin CI                                  | Cero mantenimiento                                                                            | Todo depende de la disciplina local                                  |

cocotb queda descartado por la curva de aprendizaje; la comparación contra el golden model se hace con un script Python que lee el volcado de la simulación (US-305).

## Consecuencias

**Positivas**

- Un único flujo de terminal para lint y simulación, idéntico en local y en el CI.
- Las regresiones de RTL y de Python se detectan automáticamente en cada PR.
- Como las memorias son inferidas (ADR-005), el núcleo completo y la Debug Unit se simulan en Icarus sin modelos de IP.

**Negativas**

- No se puede usar SystemVerilog (aserciones, `logic`, clases), lo que hace los testbenches más largos.
- La simulación automatizada no usa el simulador del fabricante: una diferencia de comportamiento entre Icarus y Vivado solo se vería en la placa o en una simulación manual con xsim.
- El `top` con Clock Wizard no entra en `make sim-all`; se verifica a mano en Vivado y en la placa.

**Restricciones que impone**

- Cada testbench nuevo tiene que pasar en Icarus y vivir en `hw/tb/` con el nombre `tb_*.v`.
- Un PR con el lint, un testbench o una verificación de Python en rojo no se mergea (DoD).
- El workflow de GitHub Actions vive en `.github/workflows/`.
- Nada del RTL del núcleo ni de la Debug Unit puede depender de primitivas de Xilinx; el Clock Wizard queda aislado en el `top`.

## Referencias

- PRD §7 (NFR-8, NFR-10), §8 (ADR-015); US-102, US-305.
- Uso de las herramientas: [`docs/guia-herramientas.md`](../guia-herramientas.md).
