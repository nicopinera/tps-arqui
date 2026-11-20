# Manual de usuario

Cómo instalar el software, programar la Basys 3 y usar la GUI y la CLI para cargar, correr y mirar programas en el procesador RISC-V del TP3. No hace falta conocer el código.

## 1. Qué hace falta

| Para…                          | Qué                                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| Usar la GUI o la CLI           | Python 3.13 y [uv](https://docs.astral.sh/uv/getting-started/installation/) (Windows, Linux o macOS) |
| Usar la placa                  | Basys 3, cable micro-USB **de datos**, drivers FTDI (Windows los instala solo)                       |
| Programar la placa             | Vivado 2025.2 (alcanza con el Hardware Manager) y el bitstream `top.bit`                             |
| Rearmar el bitstream o simular | Vivado 2025.2; Icarus Verilog y Verilator (`make setup`, en Linux o WSL)                             |

Sin placa también se puede usar todo: la GUI y la CLI tienen un modo **simulado** que corre el mismo programa en un modelo del pipeline, ciclo a ciclo igual que el hardware.

## 2. Instalar

```bash
git clone <repositorio>
cd tps-arqui/TP3/tools
uv sync                                    # crea el entorno con las dependencias
uv run python -m riscv_toolkit --version   # prueba
```

En Windows, si también se usa WSL sobre la misma carpeta, conviene que cada sistema tenga su entorno: `UV_PROJECT_ENVIRONMENT=.venv-windows` en Windows (el `.venv` queda para Linux).

## 3. Programar la placa

1. Conseguir el bitstream: el del release, o generarlo con `make impl` (deja `TP3/build/vivado_top/top.bit` y en `commit.txt` el commit del que salió).
2. Conectar la Basys 3 y prenderla.
3. Vivado → **Open Hardware Manager → Open Target → Auto Connect → Program Device**, elegir `top.bit`.
4. Apretar BTNC (reset). Los LEDs quedan apagados: la Debug Unit está esperando un programa.

| LED | Significa                                              |
| --- | ------------------------------------------------------ |
| LD0 | READY: hay un programa cargado, listo para correr      |
| LD1 | Corriendo (RUN) o en paso a paso                       |
| LD2 | Terminó (HALT, instrucción ilegal o ABORT)             |
| LD3 | Llegó un byte con error de paridad (se apaga con BTNC) |

## 4. La GUI

```bash
cd TP3/tools
uv run python -m riscv_toolkit ui
```

1. **Conexión.** Elegir el puerto de la placa (se detecta solo) y **Conectar**; sin placa, **Usar sin placa (simulado)**.
2. **Programa.** **Abrir** un `.asm` (hay ejemplos en `TP3/asm/`: `demos/` para programas completos y `riesgos/` para ver un riesgo por programa), editarlo si hace falta y **Ensamblar** (Ctrl+B). Los errores aparecen con el número de línea.
3. **Cargar** manda el programa a la placa por la UART. No hace falta resintetizar ni resetear la placa: cada carga limpia registros, memoria y pipeline.
4. Ejecutar:
   - **Paso**: un ciclo de reloj. **Paso xN**: N ciclos.
   - **Correr**: hasta el final del programa. **Abortar** corta un programa que no termina.
   - Las flechas de **Ciclo** recorren los ciclos ya ejecutados sin volver a ejecutar nada.
5. Mirar el estado (menú de la izquierda):

| Página    | Muestra                                                                                                        |
| --------- | -------------------------------------------------------------------------------------------------------------- |
| Pipeline  | Qué instrucción hay en cada etapa, los riesgos del ciclo (stall, flush, forwarding) y cada latch campo a campo |
| Datapath  | El diagrama del procesador con el valor de cada cable en ese ciclo                                             |
| Carta     | Instrucciones × ciclos: la figura clásica de un pipeline                                                       |
| Registros | `x0`…`x31`, con lo que cambió en el último ciclo marcado                                                       |
| Memoria   | Las palabras escritas de la memoria de datos; **Leer** trae cualquier rango                                    |
| Historial | Todos los ciclos; **Exportar sesión (.json)** y **Abrir sesión** (para verla sin placa)                        |
| Verificar | Compara el resultado con el simulador de referencia (golden model)                                             |
| Resumen   | Ciclos, CPI y cuántos riesgos hubo                                                                             |

## 5. La CLI

Para scripts o para trabajar sin ventana. Todo con `uv run python -m riscv_toolkit` desde `TP3/tools/`:

```bash
… asm ../asm/demos/fibonacci.asm -o fib.hex     # ensamblar (.hex, .bin o .lst)
… sim ../asm/demos/fibonacci.asm                # correr en el golden model
… dbg ping                                      # ¿responde la placa?
… dbg load ../asm/demos/fibonacci.asm           # cargar
… dbg run                                       # correr (Ctrl+C manda ABORT)
… dbg step 5                                    # 5 ciclos
… dbg dump                                      # estado actual sin ejecutar
… dbg --fake shell                              # sesión interactiva con la placa simulada
```

`--json` da la salida en JSON; `--port` elige el puerto si hay más de uno.

## 6. Escribir programas

- Instrucciones RV32I de la tabla del enunciado, registros `x0`…`x31` (sin nombres ABI), pseudoinstrucciones `nop`, `mv`, `j` y `ret`, etiquetas y `.word`.
- `halt` termina el programa. Si falta, el ensamblador lo agrega al final y avisa.
- Memorias de 256 palabras de instrucciones y 256 de datos; los datos iniciales se escriben con stores.
- Detalle del lenguaje: [guía del ensamblador](../guias/guia-ensamblador.md); referencia de una página: [hoja_referencia.pdf](hoja_referencia.pdf).

## 7. Si algo no anda

| Síntoma                                      | Probable causa / qué hacer                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------------------------- |
| No aparece el puerto                         | Cable solo de carga, o falta el driver FTDI. Probar otro cable                            |
| `ping` no responde                           | La placa no está programada con `top.bit`, o falta apretar BTNC después de programar      |
| LD3 prendido                                 | Errores de paridad: otro programa tiene abierto el puerto, o la velocidad no es 19200 8E1 |
| "Conectate a la placa primero" en **Cargar** | Conectar, o usar el modo simulado                                                         |
| El programa no termina                       | Un lazo sin salida: **Abortar** (o `dbg abort`). La placa queda lista para cargar otro    |
