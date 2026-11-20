# Checklist manual de la GUI (US-501)

Recorrido guiado para verificar la GUI antes de un merge y antes de la defensa. Se hace dos veces: una en modo simulado (sin placa) y otra con la Basys 3 conectada. Lo que se puede probar sin abrir ventanas (la habilitación de botones y la línea a resaltar) ya lo cubren `tests/ui/test_state.py` y `make check-py`.

La ventana abre en **1366×768** (la resolución de la maqueta, mínimo 1280×720): el recorrido se hace a ese tamaño. Ninguna página tiene que necesitar scroll horizontal, y Registros tiene que mostrar los 32 sin scroll.

## Cómo abrirla

Windows (PowerShell), con un entorno propio para no pisar el `.venv` de WSL:

```powershell
cd TP3/tools
$env:UV_PROJECT_ENVIRONMENT = ".venv-windows"
uv run python -m riscv_toolkit ui           # --fake: arranca con "Simulado" elegido
```

Linux / WSL (una sola vez: `sudo apt install libsecret-1-0`, ya incluido en `make setup`):

```bash
cd TP3/tools && uv run python -m riscv_toolkit ui --fake
```

## Recorrido

Marcá cada punto. **Modo:** S = simulado, P = placa.

| #   | Paso                                                                                                    | Esperado                                                                                         | S   | P   |
| --- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | --- | --- |
| 1   | Abrir la GUI                                                                                             | Pantalla de conexión; píldora "Desconectado"; insignia SIN CONEXIÓN; **todos** los controles de ejecución deshabilitados | [ ] | [ ] |
| 2   | Elegir el puerto y **Conectar** (o **Usar sin placa**)                                                   | Píldora "COMx · 19200 8E1 · conectado · protocolo v1" o "Simulado"; insignia `IDLE`; va a Programa | [ ] | [ ] |
| 3   | **Abrir** (Ctrl+O) `asm/demos/fibonacci.asm`                                                             | Texto en el editor; nombre del archivo al lado de los botones                                    | [ ] | [ ] |
| 4   | **AC3**: con estado `IDLE`                                                                               | Correr, Paso, Paso xN y Abortar deshabilitados; Reset habilitado; Cargar deshabilitado (falta ensamblar) | [ ] | [ ] |
| 5   | **Ensamblar** (Ctrl+B)                                                                                   | Listado con dirección, palabra, línea y fuente; Cargar se habilita                               | [ ] | [ ] |
| 6   | **AC2**: cambiar `addi` por `addx` en una línea y Ensamblar                                              | Mensaje rojo "Línea N: …"; Cargar deshabilitado                                                  | [ ] | [ ] |
| 7   | Clic en el mensaje de error                                                                              | El editor toma foco y selecciona la línea N                                                      | [ ] | [ ] |
| 8   | Corregir, Ensamblar y **Cargar** (Ctrl+L)                                                                | Estado `READY`, ciclo 0; en el listado se resalta la dirección 0000                              | [ ] | [ ] |
| 9   | Escribir algo en el editor sin ensamblar                                                                 | Cargar se deshabilita (el texto ya no es el ensamblado); Correr y Paso siguen                    | [ ] | [ ] |
| 10  | **AC5**: **Paso** (F10) tres veces con "Seguir IF"                                                       | Estado `STEPPING`, ciclo 3; el resaltado avanza una fila por paso                                | [ ] | [ ] |
| 11  | Cambiar a "Seguir WB" y dar un Paso                                                                      | El resaltado pasa a la instrucción en WB (en placa, 4 etapas más atrás; con burbuja, ninguna)    | [ ] | [ ] |
| 12  | **Paso xN** con N = 5                                                                                    | Avanza 5 ciclos de una; barra de estado con ciclo, PC, stalls y flushes                          | [ ] | [ ] |
| 13  | **AC1**: **Correr** (F5)                                                                                 | Estado `HALTED`, motivo `HALTED`; sin resaltado; Correr y Paso deshabilitados                    | [ ] | [ ] |
| 14  | **Reset** (Ctrl+R)                                                                                       | Estado `READY`, ciclo 0                                                                          | [ ] | [ ] |
| 15  | **AC4**: abrir `asm/special/infinite_loop.asm`, Ensamblar, Cargar y Correr                               | "esperando a la placa…"; solo Abortar habilitado                                                 | [ ] | [ ] |
| 16  | Durante ese RUN: mover la ventana, escribir en el editor, cambiar IF/WB                                  | La ventana responde                                                                              | [ ] | [ ] |
| 17  | **Abortar** (Shift+F5)                                                                                   | En menos de 1 s: estado `HALTED`, motivo `ABORTED`                                               | [ ] | [ ] |
| 18  | **AC6**: abrir `asm/special/ilegal.asm`; Ensamblar, Cargar, Correr                                       | Motivo `ILLEGAL`; se resalta la fila 0004 (la ilegal)                                            | [ ] | [ ] |
| 19  | Correr `infinite_loop.asm` otra vez y cerrar la ventana con la X                                         | La ventana se cierra en pocos segundos; al reconectar, la DU está en `HALTED` (no quedó corriendo) | [ ] | [ ] |
| 20  | **Desconectar**                                                                                          | "Desconectado"; todos los controles deshabilitados; el puerto se puede volver a elegir           | [ ] | [ ] |
| 21  | **Guardar** (Ctrl+S) un programa nuevo (sin archivo abierto)                                             | Diálogo para elegir dónde; aviso "Guardado en …"                                                 | [ ] | [ ] |

## Vista del pipeline (US-502)

De dónde sale cada columna: IF = la instrucción de `Snapshot.pc` en la imagen cargada; ID, EX, MEM y WB = el `instr` de IF/ID, ID/EX, EX/MEM y MEM/WB. El latch IF/ID **no** es la etapa IF. Detalle en la guía del toolkit, §15.6.

| #   | Paso                                                                                         | Esperado                                                                                         | S   | P   |
| --- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | --- | --- |
| P1  | Cargar `fibonacci.asm`, ir a **Pipeline** y dar 4 pasos                                       | El llenado del pipeline, ciclo a ciclo (IF = la del PC)                                           | [ ] | [ ] |
| P2  | Tocar la tarjeta EX                                                                          | Se elige ID/EX, la tarjeta EX queda con borde y la tabla muestra todos sus campos                | [ ] | [ ] |
| P3  | **AC4**: recorrer IF/ID, ID/EX, EX/MEM y MEM/WB con el selector                               | Cada tabla con todos los campos del protocolo, en hex y decimal                                  | [ ] | [ ] |
| P4  | **AC1**: `load_use.asm`, paso a paso                                                         | Ciclo del stall: `STALL` en IF e ID; el siguiente: burbuja en EX y la misma instrucción en ID     | [ ] | [ ] |
| P5  | **AC2**: `branch_taken.asm`                                                                  | Las instrucciones descartadas tachadas, con `FLUSH`                                               | [ ] | [ ] |
| P6  | **AC3**: `fwd_ex_mem.asm`                                                                    | `A ← EX/MEM` (o `B`) en EX y `→ A` en MEM, en el ciclo del forwarding                           | [ ] | [ ] |
| P7  | **AC5**: justo después de un salto tomado                                                    | IF muestra la instrucción del destino                                                             | [ ] | [ ] |

Desde el agregado US-306 el modo simulado corre el modelo del pipeline, así que P4 a P6 también se ven sin placa (en los mismos ciclos que en la placa, si el RTL está bien). Sacar una captura de cada uno para el informe.

## Vista Datapath

El dibujo es `docs/diagramas/datapath_pipeline.svg`. Medido = viene en el snapshot (los latches); calculado = lo combinacional, que el modelo del pipeline recalcula desde ese estado (con placa, si el RTL difiere del modelo, lo calculado puede no coincidir con la placa).

| #  | Paso                                              | Esperado                                                                                              | S   | P   |
| -- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | --- | --- |
| D1 | Abrir **Datapath** con cualquier programa cargado | El diagrama entero; rueda = zoom, arrastrar = mover, el botón "Ver entero" lo vuelve a encuadrar      | [ ] | [ ] |
| D2 | `asm/riesgos/06_load_use_stall.asm`, ciclo 4      | PC, IF/ID e ID/EX en ámbar (stall); los valores medidos en amarillo, los calculados en azul e itálica | [ ] | [ ] |
| D3 | Mismo programa, ciclo 6                           | Los cables de forwarding A y B pintados desde `ResultW`; `srcA = srcB = 0x7`                          | [ ] | [ ] |
| D4 | `asm/riesgos/08_branch_tomado_flush.asm`, ciclo 3 | IF/ID e ID/EX en rojo y el camino de `ex_target` al mux del PC                                        | [ ] | [ ] |
| D5 | Ir a otra página, cambiar de ciclo y volver       | El diagrama muestra el ciclo nuevo (no el de antes de salir)                                          | [ ] | [ ] |

## Carta de pipeline (US-503)

| #   | Paso                                                                              | Esperado                                                                                   | S   | P   |
| --- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --- | --- |
| C1  | Cargar `fibonacci.asm`, dar 15 pasos e ir a **Carta**                              | Una fila por instrucción en diagonal; las del loop (`sw`, `add`…) vuelven a aparecer en filas nuevas (AC3) | [ ] | [ ] |
| C2  | Dar Paso con la Carta abierta                                                      | Se agrega una columna; la ventana no se reinicia                                           | [ ] | [ ] |
| C3  | **AC1**: `load_use.asm` paso a paso                                                | `ID` repetido en la fila de la dependiente (el primero con relleno de STALL) y una fila "burbuja" desde EX | —   | [ ] |
| C4  | `branch_taken.asm`                                                                 | Las dos instrucciones descartadas con relleno de FLUSH y tachadas; el destino en una fila nueva | —   | [ ] |
| C5  | **AC2**: el programa de 10 instrucciones de US-103 AC4                             | Igual a la carta dibujada a mano. Sacar captura para el informe                             | —   | [ ] |
| C6  | Correr (F5) y volver a la Carta                                                    | Aviso "Solo paso a paso…"; después del salto de ciclos, filas nuevas                       | [ ] | [ ] |

## Registros y memoria (US-504)

Programa de prueba: `addi x5, x0, -1` / `addi x6, x0, 72` / `sb x6, 0(x0)` / `addi x6, x0, 105` / `sb x6, 1(x0)` / `halt`. Para ver una cadena entera: `asm/demos/hola.asm`.

| #   | Paso                                                                   | Esperado                                                                                   | S   | P   |
| --- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --- | --- |
| E1  | Cargar e ir a **Estado**                                               | 32 registros en 0, sin resaltar; "El programa todavía no escribió la memoria."             | [ ] | [ ] |
| E2  | **AC1**: Paso hasta que `addi x5` llega a WB                           | `x5` = `0xffffffff`, `-1`, `4294967295`, resaltado. Al siguiente paso deja de estar resaltado | [ ] | [ ] |
| E3  | **AC2**: Paso hasta el primer `sb`                                     | Fila `0x0000` con `48 00 00 00`, ASCII `H...`; resaltada, con el byte `+0` en relleno fuerte | [ ] | [ ] |
| E4  | Paso hasta el segundo `sb`                                             | `48 69 00 00`, `Hi..`; solo el byte `+1` en relleno fuerte                                 | [ ] | [ ] |
| E5  | **AC3**: dirección `0x0`, palabras `4`, **Leer**                       | Tabla aparte "Leído a pedido en el ciclo N" con 4 palabras, la primera `0x00006948`        | [ ] | [ ] |
| E6  | Dirección `0x11` y Leer; después `0x3fc` con 2 palabras                | Aviso "alineada a 4"; aviso "se pasa de la DMEM". No se manda nada a la placa              | [ ] | [ ] |
| E7  | Correr `infinite_loop.asm` e ir a Estado                               | Leer deshabilitado mientras corre                                                          | [ ] | [ ] |

## Historial, exportar y verificar (US-505)

| #   | Paso                                                                                   | Esperado                                                                                  | S   | P   |
| --- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | --- | --- |
| H1  | `burbuja.asm`: Cargar y 20 pasos. **AC1**: con ◀ volver 5 ciclos                       | Pipeline, latches, registros, memoria, barra de estado y línea resaltada son las de ese ciclo; la Carta marca su columna; "solo lectura" | [ ] | [ ] |
| H2  | Dar Paso estando en un ciclo viejo                                                     | Avanza desde el último y el cursor vuelve al final                                        | [ ] | [ ] |
| H3  | Correr (F5), ir a Estado y **Verificar**                                               | "✔ Coincide con el golden model."                                                         | [ ] | [ ] |
| H4  | **AC2**: Exportar; Desconectar; Reabrir el JSON                                        | Mismo programa en el editor, mismo ciclo bajo el cursor; se navega igual; Verificar coincide | [ ] | [ ] |
| H5  | **AC3**: en el JSON, cambiar un dígito del último snapshot dentro de los registros (después de los primeros 20 caracteres hex); reabrir y Verificar | Tabla con la diferencia: registro, obtenido, esperado                                     | [ ] | —   |
| H6  | Reabrir un archivo que no es una sesión (un `.json` cualquiera)                         | Aviso "no es una sesión exportada"; no cambia nada                                        | [ ] | —   |
| H7  | Verificar con `infinite_loop.asm` corriendo paso a paso                                | "El programa no terminó…"                                                                  | [ ] | [ ] |

## Rediseño con la maqueta

| #   | Paso                                                                                   | Esperado                                                                                  | S   | P   |
| --- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | --- | --- |
| M1  | Conectar a un puerto que no es la placa                                                | Aviso rojo en la pantalla de conexión con el error; sigue desconectado                    | —   | [ ] |
| M2  | Abrir `asm/errores/falta_coma.asm` (y los demás de esa carpeta)                        | ● al lado del nombre; Problemas "1 error" con la línea y "Ir"; listado vacío con su aviso; Cargar deshabilitado con el motivo en el tooltip | [ ] | [ ] |
| M3  | `advertencia_sin_halt.asm`                                                             | "Sin errores · 1 advertencia"; se puede cargar                                            | [ ] | [ ] |
| M4  | `burbuja.asm`: Cargar y pasos                                                          | Programa en modo ejecución: fuente de solo lectura, línea marcada, etiqueta de etapa en cada línea; "Editar" vuelve al editor | [ ] | [ ] |
| M5  | `infinite_loop.asm`: Correr                                                            | Banner "Corriendo desde hace X s" con barra; insignia RUN rellena; Abortar rojo; **Esc** aborta | [ ] | [ ] |
| M6  | Pipeline, Etapas: tocar cada franja de latch                                           | Se marca y se ve abajo, agrupado en Datos / Control / Depuración                          | [ ] | [ ] |
| M7  | `load_use.asm` paso a paso hasta el stall                                              | IF e ID en ámbar "se congela"; al ciclo siguiente EX rayada (burbuja); "Qué pasó" explica el load-use; `stall = 1` | —   | [ ] |
| M8  | `branch_taken.asm` hasta el beq tomado                                                 | IF e ID en rojo y tachadas; EX con "tomado → 0x…"; en la Carta, ✕ al ciclo siguiente      | —   | [ ] |
| M9  | `fwd_ex_mem.asm` hasta un forwarding                                                   | Chip A/B en EX, borde en la etapa fuente, flecha debajo; en ID/EX el rs1_data/rs2_data viejo marcado | —   | [ ] |
| M10 | Pipeline, Latches y Campos                                                             | Los 4 latches juntos; la tabla de qué es cada campo                                       | [ ] | [ ] |
| M11 | Carta: tocar el número de un ciclo                                                     | Va a ese ciclo (chip "Revisando"); la columna queda marcada                               | [ ] | [ ] |
| M12 | Registros: cambiar el formato; dar un paso                                             | Columnas según el formato; "Cambió en este paso" con quién lo escribió; "Se escribe al final de este ciclo" | [ ] | [ ] |
| M13 | Memoria: Desde 0x0 Hasta 0x1c, Leer                                                    | Chip "Leído a pedido · ciclo N" y 8 palabras; "Última escritura" en la tabla de arriba    | [ ] | [ ] |
| M14 | Historial: tocar una fila                                                              | Banner "Estás viendo el ciclo X de N…"; "Volver al ciclo actual" vuelve                   | [ ] | [ ] |
| M15 | Verificar con una diferencia (checklist H5)                                            | Banner rojo; fila en rojo; "Solo diferencias"; "Por dónde empezar" con *Ir al ciclo N*     | [ ] | [ ] |
| M16 | Resumen después de un programa paso a paso                                             | Las 6 cuentas, barras por ciclo con el color de los riesgos, reparto y mezcla            | [ ] | [ ] |

## Solo con placa

| #   | Paso                                                                     | Esperado                                                                 | P   |
| --- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------ | --- |
| 22  | Desenchufar el USB con la GUI conectada y apretar Paso                   | Aviso con el error del puerto; la GUI no queda en "esperando a la placa…" | [ ] |
| 23  | Con la DU en `RUN` desde una sesión anterior, abrir la GUI y conectar    | Estado `RUN`, solo Abortar habilitado; Abortar la detiene                | [ ] |
