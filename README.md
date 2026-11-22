# Trabajos Prácticos - Arquitectura de Computadoras 2026

## UNC - Facultad de Ciencias Exactas, Físicas y Naturales

## Integrantes

- Krede, Julián
- Piñera, Nicolás

---

Este repositorio tiene los tres trabajos prácticos de la materia, desarrollados en Verilog sobre la placa **Basys 3** (Artix-7 XC7A35T). Cada TP usa lo que se construyó en el anterior: la ALU del TP1 se controla por UART en el TP2, y en el TP3 esa UART es el canal con el que una PC programa y observa un procesador RISC-V segmentado.

| TP | Tema | Qué se construyó | Informe |
| -- | ---- | ---------------- | ------- |
| **TP1** | ALU | ALU parametrizable (8 bits por defecto) con suma, resta, operaciones lógicas y desplazamientos. Los operandos y el código de operación se cargan desde los switches de la placa | [`docs/tp1/informe/informe_tp1.pdf`](docs/tp1/informe/informe_tp1.pdf) |
| **TP2** | UART | Transmisor y receptor UART (19200 bps, 8E1) con máquinas de estado y generador de baud rate, integrados con la ALU del TP1: la PC manda los operandos por puerto serie y recibe el resultado | [`TP2/README.md`](TP2/README.md) |
| **TP3** | Pipeline RISC-V | Procesador RV32I de 5 etapas con forwarding y manejo de riesgos, una Debug Unit que lo programa, ejecuta y vuelca por UART, y software de PC (ensamblador, simulador, CLI y GUI) | [`TP3/README.md`](TP3/README.md) |

## TP3 en pocas palabras

- **Núcleo:** RV32I segmentado en IF, ID, EX, MEM y WB, con las 32 instrucciones del enunciado más `HALT`. Tiene forwarding desde EX/MEM y MEM/WB, stall de un ciclo por load-use y predicción _not-taken_. Los `jal` se resuelven en ID y los branches y `jalr` en EX. El CPI medido en los programas de demostración va de 1,23 a 1,44.
- **Debug Unit:** recibe comandos por UART para cargar el programa sin resintetizar, ejecutarlo de corrido o ciclo a ciclo y abortarlo. Devuelve los 32 registros, los 4 latches y la memoria de datos usada. El paso a paso se hace con _clock enable_, sin tocar el reloj.
- **Timing:** a 100 MHz no cierra, y el camino crítico está en la Debug Unit, no en el pipeline. Con un barrido de frecuencias se eligió **85 MHz** (WNS = +0,345 ns), que se genera con un Clock Wizard.
- **Software de PC** (Python 3.13): ensamblador propio, desensamblador, golden model, modelo del pipeline ciclo a ciclo, CLI e interfaz gráfica en Flet con el datapath animado.
- **Verificación:** testbenches autoverificables por módulo, programas con firma contrastados con el golden model (también con enable aleatorio), simulación del sistema completo por la UART y CI en GitHub Actions.

## Estructura del repositorio

```
tps-arqui/
├── TP1/               ALU: fuentes, testbench y restricciones
├── TP2/               UART + ALU: fuentes, restricciones, script de prueba e informe
├── TP3/
│   ├── hw/            RTL (núcleo, Debug Unit, UART), testbenches, IP, restricciones, scripts y reportes de Vivado
│   ├── asm/           Programas en ensamblador: pruebas, demos, casos de riesgo y especiales
│   ├── tools/         Software de PC (paquete riscv_toolkit)
│   ├── Makefile       Simulación, verificación, implementación y reportes
│   ├── README.md      Informe final
│   └── CHANGELOG.md   Historial de versiones
├── docs/
│   ├── tp1/           Informe del TP1 en LaTeX
│   ├── adr/           20 decisiones de diseño del TP3
│   ├── interfaces/    Contratos entre módulos
│   ├── diagramas/     Datapath, arquitectura y FSM de la Debug Unit (drawio + SVG)
│   ├── informe/       Respaldo del informe: timing, métricas y datos
│   ├── manual/        Manual de usuario y hoja de referencia de la ISA
│   ├── guias/         Guías de estudio de cada parte del TP3
│   ├── defensa/       Guion de la defensa
│   ├── PRD-pipeline-riscv.md   Plan del TP3: requerimientos, hitos e historias de usuario
│   └── protocolo.md   Protocolo PC ↔ Debug Unit
└── enunciados/        Enunciados de la cátedra
```

## Cómo usarlo

**TP1 y TP2** son proyectos de Vivado: hay que agregar las fuentes de `src/` y el `.xdc` de `constrs/`. Para probar el TP2 con la placa conectada:

```bash
cd TP2
python3 test_uart_alu.py                 # casos de prueba
python3 test_uart_alu.py -i              # modo interactivo
python3 test_uart_alu.py -p /dev/ttyUSB0 # otro puerto serie
```

**TP3** se maneja con el `Makefile`, en Linux o WSL:

```bash
cd TP3
make setup        # Icarus, Verilator y el entorno de Python (uv)
make check        # lo mismo que el CI: lint, testbenches, programas, verificación cruzada y Python
make sim-system   # todos los programas por la UART simulada al top
make impl         # síntesis, implementación y bitstream con Vivado 2025.2
```

Y con la placa, desde `TP3/tools/`:

```bash
uv run python -m riscv_toolkit ui                              # interfaz gráfica
uv run python -m riscv_toolkit asm ../asm/demos/fibonacci.asm  # ensamblar un programa
uv run python -m riscv_toolkit dbg ping                        # probar la conexión con la placa
```

El detalle de cada comando está en el Anexo C de [`TP3/README.md`](TP3/README.md) y en el [manual de usuario](docs/manual/usuario.md).

## Herramientas

- Vivado 2025.2 para síntesis, implementación y Clock Wizard
- Icarus Verilog y Verilator para simulación y lint
- Python 3.13 con `uv`, pytest, ruff y mypy
- GitHub Actions para CI y releases (al pushear un tag `vX.Y` se crea el release con las notas de [`TP3/CHANGELOG.md`](TP3/CHANGELOG.md))
