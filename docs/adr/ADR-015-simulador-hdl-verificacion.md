# ADR-015 — Simulador HDL y framework de verificación

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-102
- **Relacionados:** ADR-005 (memoria inferida, sin IP), ADR-011 (Python), ADR-014 (golden model), ADR-016 (Clock Wizard), ADR-020 (versión de Vivado)

## Contexto

El proyecto necesita simular muchos módulos (ALU, banco de registros, unidades de riesgo, núcleo completo, Debug Unit) y, sobre todo, correr la suite de programas de prueba contra el RTL de forma repetible. US-102 pide un `make sim TB=…` que diga `PASS`/`FAIL` sin mirar formas de onda, y un `make sim-all` que resuma todo.

Hay tres opciones de simulador con perfiles distintos: el que viene con Vivado (ya instalado y alineado con la síntesis), uno libre y liviano (scriptable e instalable en CI) y un framework en Python (que reutiliza el golden model).

## Decisión

### Simulador

- **Vivado xsim es el simulador de referencia**, corrido en modo batch desde `hw/scripts/sim.tcl` (`make sim`, `make sim-all`).
- **Los testbenches se escriben en Verilog-2001 estándar**, sin características de SystemVerilog ni primitivas exclusivas de Xilinx, para que también corran en **Icarus Verilog**.
- Los testbenches son autoverificables: usan `hw/tb/common/tb_utils.vh` (`check_eq`, `tb_finish`) e imprimen `TEST PASSED` o `TEST FAILED (N errores)`.
- Los programas se cargan en la IMEM con `$readmemh` a partir del `.hex` del ensamblador (ADR-013).
- Las ondas se generan solo bajo demanda (`WAVES=1`): `.wdb` en xsim y `.vcd` en Icarus (se ven con GTKWave).

### Integración continua (GitHub Actions)

En cada push y PR:

1. **Python:** `ruff check` y `pytest` con cobertura sobre `tools/` (NFR-10).
2. **HDL:** se instala Icarus Verilog y se corren todos los testbenches que no dependen de IP de Xilinx (`make sim-all SIM=icarus`).

Los testbenches que dependen de IP (por ejemplo, el `top` con el Clock Wizard de ADR-016) se marcan como solo-xsim y se corren localmente.

## Alternativas consideradas

| Opción                                                 | Ventajas                                                                                         | Desventajas                                                                                       |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| **(a) xsim + testbenches Verilog-2001 portables** (elegida) | Ya instalado; mismo entorno que la síntesis; simula IP de Xilinx; los testbenches también corren en Icarus | xsim es lento para arrancar y pesado para CI                                                      |
| (b) Icarus + GTKWave como base                         | Rápido, liviano, scriptable; ideal para CI                                                       | No simula IP de Xilinx; puede diferir de Vivado en detalles de Verilog                             |
| (c) cocotb (testbenches en Python)                     | Reutiliza el golden model directamente; tests muy expresivos                                     | Otra herramienta que aprender; requiere un simulador por debajo (Icarus o similar)                |

**CI**

| Opción                                 | Ventajas                                                                 | Desventajas                                                            |
| -------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| **Python + Icarus** (elegida)          | Detecta regresiones de hardware y de software en cada PR, sin depender de la máquina de nadie | Mantener el workflow y la portabilidad de los testbenches              |
| Solo Python                            | Workflow trivial                                                         | Las regresiones de RTL solo aparecen si alguien corre `make sim-all`   |
| Sin CI                                 | Cero mantenimiento                                                       | Todo depende de la disciplina local                                    |

Se elige xsim como base porque es el entorno que ya usa el equipo y el mismo con el que se sintetiza. Exigir Verilog-2001 permite sumar Icarus en CI casi sin costo. cocotb queda descartado por la curva de aprendizaje; la comparación contra el golden model se hace con un script Python que lee el volcado de la simulación (US-305).

## Consecuencias

**Positivas**

- Las regresiones de RTL y de Python se detectan automáticamente en cada PR.
- Un testbench que pasa en xsim y en Icarus tiene menos probabilidad de depender de un comportamiento particular de un simulador.
- Como las memorias son inferidas (ADR-005), el núcleo completo se simula en Icarus sin modelos de IP.

**Negativas**

- No se puede usar SystemVerilog (aserciones, `logic`, clases), lo que hace los testbenches más largos.
- `sim.tcl` y el Makefile tienen que soportar los dos simuladores (`SIM=xsim|icarus`).
- Puede haber diferencias sutiles entre simuladores (por ejemplo, en el orden de eventos); si aparecen, xsim es la referencia.

**Restricciones que impone**

- Cada testbench nuevo tiene que pasar en los dos simuladores, salvo los marcados explícitamente como solo-xsim.
- El workflow de GitHub Actions vive en `.github/workflows/` y forma parte del DoD: un PR con CI en rojo no se mergea.
- Nada del RTL del núcleo ni de la Debug Unit puede depender de primitivas de Xilinx; el Clock Wizard queda aislado en el `top`.

## Referencias

- PRD §7 (NFR-8, NFR-10), §8 (ADR-015); US-102, US-305.
