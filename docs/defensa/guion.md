# Guion de la demostración (US-605)

Unos 10 minutos con la placa y la GUI. Cada paso dice qué hacer, qué tiene que verse y qué explicar. Si algo falla en la placa, el **plan B** del final muestra lo mismo sin hardware.

## Antes de entrar (checklist de hardware)

| #   | Qué                                                                                                                              | ¿Listo? |
| --- | -------------------------------------------------------------------------------------------------------------------------------- | ------- |
| H1  | Basys 3, cable micro-USB de datos (no solo de carga) y una notebook con los drivers FTDI                                         | [ ]     |
| H2  | Bitstream de la versión que se presenta: `make impl` (o el del release) y `build/vivado_top/commit.txt` igual al commit del repo | [ ]     |
| H3  | Placa programada desde Vivado (Hardware Manager → Program Device) y LEDs apagados después del BTNC                               | [ ]     |
| H4  | `uv run python -m riscv_toolkit dbg ping` responde con la versión del protocolo                                                  | [ ]     |
| H5  | GUI abierta (`uv run python -m riscv_toolkit ui`), conectada, con el puerto detectado                                            | [ ]     |
| H6  | Las sesiones del plan B (`docs/defensa/sesiones/`) se abren en la GUI                                                            | [ ]     |

## Recorrido

| #   | Acción                                                                          | Qué se ve                                                                                       | Qué explicar                                                                                                     |
| --- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| 1   | Abrir `asm/riesgos/06_load_use_stall.asm`, **Ensamblar** y **Cargar**           | LED0 (READY). En **Programa**, el listado con las direcciones                                   | El ensamblador propio (dos pasadas) y el `LOAD` por la UART: limpia memoria, registros y pipeline (ADR-009)      |
| 2   | **Paso** hasta el ciclo 4 y mirar **Pipeline**                                  | `STALL` en IF e ID, burbuja que entra a EX                                                      | El load-use: el dato del `lw` recién está al final de MEM. La Hazard Unit congela PC e IF/ID y vacía ID/EX       |
| 3   | Ir a **Datapath** en el mismo ciclo, después ciclo 6                            | Ciclo 4: PC, IF/ID e ID/EX marcados. Ciclo 6: los cables de forwarding desde `ResultW`          | Medido (snapshot) contra calculado (modelo). El forwarding desde MEM/WB resuelve lo que el stall no              |
| 4   | Cargar `08_branch_tomado_flush.asm` y avanzar hasta el ciclo 3                  | IF/ID e ID/EX en rojo, el camino de `ex_target` al mux del PC                                   | El branch se resuelve en EX (ADR-006): se pierden 2 ciclos. Las "trampa" nunca escriben                          |
| 5   | **Carta**                                                                       | Instrucciones × ciclos, con la burbuja y el flush                                               | La figura de "Segmentado" del enunciado, armada con los snapshots reales                                         |
| 6   | Cargar `demos/fibonacci.asm` y **Correr** (RUN)                                 | LED1 durante la ejecución, LED2 (HALTED) al final; registros y memoria con los cambios marcados | Modo continuo: `RUN` = ACK + snapshot final. El pipeline queda vacío al terminar (4 `valid` en 0)                |
| 7   | **Reprogramación**: cargar `demos/burbuja.asm` sin resetear la placa y correrlo | El vector ordenado en **Memoria**                                                               | Se reprograma sin resintetizar: la IMEM sobrante se rellena con HALT, para que no corran restos del anterior     |
| 8   | Cargar `asm/special/infinite_loop.asm`, **Correr** y después **Abortar**        | Sigue en RUN hasta el ABORT; snapshot con motivo `ABORTED` y el contador de vueltas en `x1`     | La pregunta "¿qué pasa sin HALT?": relleno con HALT + HALT del ensamblador + `ABORT` (ADR-010)                   |
| 9   | **Verificar** (contra el golden model)                                          | "Igual al golden model" para el último programa terminado                                       | El ISS en Python como referencia; en el repo, `make verify` y `make sim-system` lo hacen para toda la suite      |
| 10  | (Si preguntan por timing) mostrar `docs/informe/timing.md`                      | El camino crítico y el barrido de frecuencia                                                    | El camino crítico es de la Debug Unit (lectura de la DMEM para el snapshot), no del procesador; el skew es chico |

## Plan B: sin placa

1. En la GUI, desconectado, ir a **Historial → Abrir sesión** y elegir uno de `docs/defensa/sesiones/`:

| Sesión                                | Para el paso |
| ------------------------------------- | ------------ |
| `riesgos_06_load_use_stall.json`      | 2 y 3        |
| `riesgos_08_branch_tomado_flush.json` | 4 y 5        |
| `riesgos_12_load_use_y_branch.json`   | 2 a 5 juntos |
| `demos_fibonacci.json`                | 6            |
| `demos_burbuja.json`                  | 7            |

   Se recorren ciclo a ciclo igual que en vivo (Pipeline, Datapath, Carta, Registros, Memoria).
2. Sin sesión: en la pantalla de conexión, **Usar sin placa (simulado)** corre los mismos programas en el modelo del pipeline, que coincide ciclo a ciclo con el RTL (`verify_board --step` en lockstep).
3. Para el ABORT: `make sim TB=tb_top_sin_halt` muestra el lazo cortado con ABORT en el sistema completo simulado (`docs/informe/datos/experimento_sin_halt.txt`).

Las sesiones de esta carpeta se generaron con `uv run python -m scripts.sesiones_defensa` en la placa simulada (`"simulado": true`). Cuando la placa esté validada, conviene reemplazarlas por sesiones exportadas desde la GUI con la placa (**Historial → Exportar sesión (.json)**), con los mismos nombres.

## Ensayo (AC1)

| Fecha | Máquina | Duración | Qué falló | Arreglo |
| ----- | ------- | -------- | --------- | ------- |
|       |         |          |           |         |
