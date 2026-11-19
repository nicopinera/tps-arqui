# Checklist manual de la GUI (US-501)

Recorrido guiado para verificar la GUI antes de un merge y antes de la defensa. Se hace dos veces: una en modo simulado (sin placa) y otra con la Basys 3 conectada. Lo que se puede probar sin abrir ventanas (la habilitación de botones y la línea a resaltar) ya lo cubren `tests/ui/test_state.py` y `make check-py`.

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
| 1   | Abrir la GUI                                                                                             | Ventana con menú lateral, barra de conexión "Desconectado" y **todos** los controles deshabilitados | [ ] | [ ] |
| 2   | Elegir el puerto (o "Simulado") y **Conectar**                                                           | Indicador "Conectado a COMx · protocolo v1" o "Simulado · protocolo v1"; estado `IDLE`             | [ ] | [ ] |
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
| 18  | **AC6**: programa `addi x1, x0, 5` / `.word 0xffffffff` / `halt`; Ensamblar, Cargar, Correr              | Motivo `ILLEGAL`; se resalta la fila 0004 (la ilegal)                                            | [ ] | [ ] |
| 19  | Correr `infinite_loop.asm` otra vez y cerrar la ventana con la X                                         | La ventana se cierra en pocos segundos; al reconectar, la DU está en `HALTED` (no quedó corriendo) | [ ] | [ ] |
| 20  | **Desconectar**                                                                                          | "Desconectado"; todos los controles deshabilitados; el puerto se puede volver a elegir           | [ ] | [ ] |
| 21  | **Guardar** (Ctrl+S) un programa nuevo (sin archivo abierto)                                             | Diálogo para elegir dónde; aviso "Guardado en …"                                                 | [ ] | [ ] |

## Vista del pipeline (US-502)

De dónde sale cada columna: IF = la instrucción de `Snapshot.pc` en la imagen cargada; ID, EX, MEM y WB = el `instr` de IF/ID, ID/EX, EX/MEM y MEM/WB. El latch IF/ID **no** es la etapa IF. Detalle en la guía del toolkit, §15.6.

| #   | Paso                                                                                         | Esperado                                                                                         | S   | P   |
| --- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | --- | --- |
| P1  | Cargar `fibonacci.asm`, ir a **Pipeline** y dar 4 pasos                                       | Simulado: 5 instrucciones seguidas (IF = la del PC). Placa: el llenado del pipeline, ciclo a ciclo | [ ] | [ ] |
| P2  | Tocar la tarjeta EX                                                                          | Se elige ID/EX, la tarjeta EX queda con borde y la tabla muestra todos sus campos                | [ ] | [ ] |
| P3  | **AC4**: recorrer IF/ID, ID/EX, EX/MEM y MEM/WB con el selector                               | Cada tabla con todos los campos del protocolo, en hex y decimal                                  | [ ] | [ ] |
| P4  | **AC1**: `load_use.asm`, paso a paso                                                         | Ciclo del stall: `STALL` en IF e ID; el siguiente: burbuja en EX y la misma instrucción en ID     | —   | [ ] |
| P5  | **AC2**: `branch_taken.asm`                                                                  | Las instrucciones descartadas tachadas, con `FLUSH`                                               | —   | [ ] |
| P6  | **AC3**: `fwd_ex_mem.asm`                                                                    | `A ← EX/MEM` (o `B`) en EX y `→ A` en MEM, en el ciclo del forwarding                           | —   | [ ] |
| P7  | **AC5**: justo después de un salto tomado                                                    | IF muestra la instrucción del destino                                                             | [ ] | [ ] |

P4 a P6 solo se ven en la placa: el modo simulado no tiene Hazard Unit. Sacar una captura de cada uno para el informe.

## Solo con placa

| #   | Paso                                                                     | Esperado                                                                 | P   |
| --- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------ | --- |
| 22  | Desenchufar el USB con la GUI conectada y apretar Paso                   | Aviso con el error del puerto; la GUI no queda en "esperando a la placa…" | [ ] |
| 23  | Con la DU en `RUN` desde una sesión anterior, abrir la GUI y conectar    | Estado `RUN`, solo Abortar habilitado; Abortar la detiene                | [ ] |
