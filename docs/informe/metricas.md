# Métricas del sistema (US-603)

Recursos, potencia y rendimiento del diseño final (85 MHz con MMCM, Basys 3 `xc7a35tcpg236-1`). Las tablas salen de [datos/reportes_vivado.md](datos/reportes_vivado.md), generado por `make reportes` desde `TP3/hw/reports/top_util.rpt`, `top_util_hier.rpt`, `top_power.rpt` y `docs/informe/datos/cpi.csv` (`make verify`).

## 1. Utilización total

| Recurso                   | Usado     | Disponible    | %           |
| ------------------------- | --------- | ------------- | ----------- |
| Slice LUTs                | 3945      | 20 800        | 18,97       |
| LUT como lógica           | 3257      | 20 800        | 15,66       |
| LUT como memoria (LUTRAM) | 688       | 9600          | 7,17        |
| Flip-flops                | 2975      | 41 600        | 7,15        |
| F7 / F8 Muxes             | 608 / 147 | 16 300 / 8150 | 3,73 / 1,80 |
| Block RAM                 | 0         | 50            | 0           |
| DSP                       | 0         | 90            | 0           |
| Pines (IOB)               | 8         | 106           | 7,55        |
| BUFG                      | 2         | 32            | 6,25        |
| MMCM                      | 1         | 5             | 20          |

El diseño usa **menos del 20 % de la FPGA**, así que el tamaño no es un problema. Lo que más pesa son los LUT, por dos motivos: las memorias están en **LUTRAM** y no en BRAM (ADR-005), y hay muchos **multiplexores anchos** (lectura del banco, forwarding, selección de bytes del snapshot), que explican también los F7/F8. No se usan BRAM ni DSP: la ALU no multiplica (RV32I base) y las memorias son distribuidas. Los dos BUFG son el reloj del sistema y la realimentación del MMCM.

## 2. Utilización por módulo

| Módulo                                 | LUTs                  | LUTRAM | FF                    | Qué ocupa                                                                                                                                            |
| -------------------------------------- | --------------------- | ------ | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Núcleo** (`riscv_core`)              | 3082                  | 688    | 1916                  |                                                                                                                                                      |
| ↳ banco de registros                   | 890                   | 0      | 992                   | 31 registros × 32 bits en FF (`x0` no se guarda) y los muxes de 32 a 1 de los tres puertos de lectura (rs1, rs2, Debug Unit)                         |
| ↳ IF (con IMEM)                        | 226                   | 176    | 32                    | IMEM de 256 palabras en LUTRAM y el PC                                                                                                               |
| ↳ MEM (con DMEM y bitmap)              | 732                   | 512    | 265                   | DMEM de 256 palabras con escritura por byte y dos puertos de lectura (núcleo y Debug Unit); bitmap de 256 bits + contador de 9                       |
| ↳ latches IF/ID, ID/EX, EX/MEM, MEM/WB | 123 / 401 / 336 / 350 | 0      | 105 / 223 / 157 / 139 | Los campos de PRD §3.2; los LUT son la lógica de enable, flush y burbuja de cada campo, más la lógica de las etapas que Vivado agrupa con cada latch |
| **Debug Unit**                         | 783                   | 0      | 1001                  |                                                                                                                                                      |
| ↳ `du_dumper`                          | 532                   | 0      | 721                   | Copia de los 4 latches (648 FF) para que el snapshot sea de un solo ciclo, y la selección de cada byte a enviar                                      |
| ↳ `du_loader`                          | 108                   | 0      | 130                   | Contadores de carga, relleno con HALT y limpieza                                                                                                     |
| ↳ `du_cmd_fsm`                         | 110                   | 0      | 100                   | Intérprete de comandos y máquina de estados                                                                                                          |
| **UART RX**                            | 58                    | 0      | 21                    | Igual que en el TP2                                                                                                                                  |
| **top**                                | 1                     | 0      | 8                     | Sincronizadores de `rx` y reset, LEDs                                                                                                                |

**Lectura.** El **núcleo ocupa el 78 % de los LUT**. Dentro del núcleo, lo más grande es el **banco de registros**: casi 1000 FF y 890 LUT de multiplexores. Le siguen las memorias.

**Memorias en LUTRAM (restricción de ADR-005):** IMEM y DMEM ocupan juntas **688 LUT de memoria** (176 + 512), el 17 % de todos los LUT del diseño.

- Cada LUT de memoria guarda 64 bits, así que una memoria de 256 × 32 bits necesita como mínimo 128.
- La **DMEM usa 4 veces eso** porque tiene dos puertos de lectura combinacional (el del pipeline y el de la Debug Unit) más la dirección de escritura, y cada dirección distinta necesita su propia copia de la memoria en LUTRAM.
- En BRAM, cada memoria (8 Kb) entraría en un bloque de 18 Kb, pero la lectura pasaría a ser sincrónica (roadmap #5).

**La Debug Unit es un 20 % del diseño.** Casi todo es la copia de los latches en `du_dumper`.

**`DEBUG_TRACE` (ADR-017):**

- Agrega **96 FF** en el pipeline: el campo `instr` de 32 bits en ID/EX, EX/MEM y MEM/WB; IF/ID ya lo tiene.
- Agrega otros 96 en la copia del dumper.
- Con `DEBUG_TRACE = 0` esos campos quedan en constante y Vivado los eliminaría. No se midió con una síntesis aparte.

## 3. Potencia

| Concepto                 | Valor     |
| ------------------------ | --------- |
| Total                    | 0,210 W   |
| Estática del dispositivo | 0,072 W   |
| Dinámica                 | 0,138 W   |
| ↳ MMCM                   | 0,122 W   |
| ↳ Reloj (red y BUFG)     | 0,007 W   |
| ↳ Señales                | 0,004 W   |
| ↳ Lógica                 | 0,002 W   |
| ↳ E/S                    | 0,002 W   |
| ↳ LUTRAM                 | < 0,001 W |
| Temperatura de juntura   | 26,1 °C   |

**Lectura.** Es una estimación **vectorless**: Vivado supone una tasa de conmutación típica, sin actividad simulada. Sirve para comparar, no como medición.

- **Lo que más consume es el MMCM**: 0,122 W, el 88 % de la potencia dinámica. Es un bloque analógico con un VCO de 1 GHz funcionando todo el tiempo. La lógica del procesador, en cambio, consume muy poco (milivatios).
- Sin el MMCM, a 100 MHz directo, el total era de **0,094 W**.
- La potencia estática (0,072 W) es la del chip encendido y no depende del diseño: es la misma que en el TP2.

## 4. Rendimiento

Los 59 programas de la suite corridos en el núcleo (`make verify`, [cpi.csv](datos/cpi.csv)):

| Medida                                | Valor        |
| ------------------------------------- | ------------ |
| Ciclos totales                        | 3068         |
| Instrucciones retiradas               | 2281         |
| **CPI agregado**                      | **1,345**    |
| Ciclos perdidos por load-use (stalls) | 90 (2,9 %)   |
| Ciclos perdidos por control (flush)   | 461 (15,0 %) |
| Llenado del pipeline (4 por programa) | 236 (7,7 %)  |
| Tiempo total a 85 MHz                 | 36,1 µs      |

CPI de los programas "reales" (demos), donde el llenado pesa poco:

| Programa       | Ciclos | Instrucciones | CPI   | Stalls | Control | Tiempo a 85 MHz |
| -------------- | ------ | ------------- | ----- | ------ | ------- | --------------- |
| `burbuja`      | 383    | 270           | 1,419 | 28     | 81      | 4,51 µs         |
| `copia_cadena` | 122    | 92            | 1,326 | 12     | 14      | 1,44 µs         |
| `factorial`    | 232    | 164           | 1,415 | 0      | 64      | 2,73 µs         |
| `fibonacci`    | 188    | 145           | 1,297 | 0      | 39      | 2,21 µs         |
| `hola`         | 130    | 96            | 1,354 | 14     | 16      | 1,53 µs         |
| `subrutina`    | 381    | 309           | 1,233 | 0      | 68      | 4,48 µs         |
| `suma_arreglo` | 88     | 61            | 1,443 | 8      | 15      | 1,04 µs         |

**Lectura.** El CPI ideal de un pipeline es 1. Las pérdidas vienen sobre todo de los **saltos** (15 % de los ciclos), no de los datos (3 %):

- **Saltos:** con _predict not-taken_ y el branch resuelto en EX, cada salto tomado o `jalr` cuesta 2 ciclos y cada `jal` cuesta 1 (ADR-006). Los programas con lazos (`burbuja`, `factorial`, `subrutina`) son los que más pierden.
- **Datos:** el forwarding resuelve todas las dependencias salvo load-use, que cuesta un ciclo y solo aparece donde se usa un dato recién leído (`burbuja`, `copia_cadena`).

Las penalidades por tipo de riesgo se verifican una por una con los programas de `asm/riesgos/` (por ejemplo, `08_branch_tomado_flush`: 2 ciclos de flush más el del HALT). Los programas cortos de prueba tienen CPI alto (2 a 6) porque los 4 ciclos de llenado pesan mucho sobre pocas instrucciones; no representan el rendimiento real.

**Tiempo de ejecución.** A 85 MHz, un ciclo dura 11,8 ns. El programa más largo de la suite (`burbuja`) corre en 4,5 µs. Lo que domina el tiempo en la placa es la UART: un snapshot de unos 230 bytes a 19200 bps tarda unos 130 ms, 30 000 veces más que la ejecución.

## 5. Comparación con el TP2

| Medida                  | TP2 (ALU + UART)        | TP3 (procesador completo) | Relación |
| ----------------------- | ----------------------- | ------------------------- | -------- |
| Slice LUTs              | 123                     | 3945                      | ×32      |
| Flip-flops              | 95                      | 2975                      | ×31      |
| Frecuencia              | 100 MHz (reloj directo) | 85 MHz (MMCM)             |          |
| WNS                     | +4,899 ns a 100 MHz     | +0,345 ns a 85 MHz        |          |
| Potencia total estimada | 0,073 W                 | 0,210 W                   | ×2,9     |

El TP2 cerraba con 4,9 ns de sobra porque su camino más largo era la ALU entre dos registros. En el TP3, el camino crítico encadena sumadores, una lectura de memoria y varios muxes en un solo ciclo, y cruza el chip entre la Debug Unit y el núcleo. Por eso la frecuencia baja a 85 MHz aunque la FPGA siga casi vacía. La potencia se triplica, pero casi toda la diferencia es el MMCM, no la lógica.
