# Caso de estudio: síntesis y camino crítico de la Debug Unit

Qué encontramos al sintetizar por primera vez la Debug Unit (DU) en Vivado, cómo leímos el reporte, qué cambiamos en `du_dumper` para acortar el camino crítico y qué mostró la segunda corrida. Es un caso real del proyecto, con los números de los reportes de `TP3/hw/reports/du_ooc_*.rpt`.

Para lo básico (qué es WNS, cómo está armado un reporte, checklist) ver [`guia-reporte-timing.md`](guia-reporte-timing.md). Esta guía aplica eso a un problema concreto.

---

## 1. Por qué sintetizar la DU sola, y cómo

Cuando terminamos el último submódulo de la DU (`du_dumper` con `MEM_DATA`, US-408), la DU quedó completa pero **sin núcleo**: no hay todavía un `top.v` con las dos cosas juntas. Igual conviene sintetizarla ahora, para saber temprano:

1. si todo el Verilog es **sintetizable** (sin latches, sin construcciones que solo existen en simulación);
2. **cuánto ocupa** de la FPGA;
3. si sus caminos **internos** llegan a **100 MHz** (10 ns entre flancos).

**El problema:** `debug_unit` tiene ~800 bits de puertos (solo los 4 latches son 648) y la Basys 3 tiene ~100 pines. No puede ser el top.

**La solución: síntesis _out-of-context_ (OOC).** Vivado sintetiza el módulo como un bloque que después va a ir **adentro** de otro diseño, sin asignarle pines. Es lo mismo que pide el PRD para el núcleo (US-210, AC5).

| Archivo                           | Qué hace                                                                                         |
| --------------------------------- | ------------------------------------------------------------------------------------------------ |
| `TP3/hw/scripts/synth_du_ooc.tcl` | `synth_design -mode out_of_context`, place & route, reportes y un resumen con WNS, WHS y latches |
| `TP3/hw/constraints/du_ooc.xdc`   | una sola línea: `create_clock -period 10.000 [get_ports clock]` (100 MHz)                        |

```powershell
cd TP3
mkdir build\vivado_du_ooc -Force
& "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source hw/scripts/synth_du_ooc.tcl -log build/vivado_du_ooc/vivado.log -journal build/vivado_du_ooc/vivado.jou
```

---

## 2. Primera corrida: los números

| Qué         | Valor                  | Lectura                                           |
| ----------- | ---------------------- | ------------------------------------------------- |
| WNS (setup) | **+0,859 ns**          | cumple, pero el peor camino usa 9,09 de los 10 ns |
| WHS (hold)  | +0,100 ns              | cumple                                            |
| Latches     | 0                      | bien                                              |
| LUTs        | 865 (4,2 % de 20 800)  | chico                                             |
| Flip-flops  | 1017 (2,4 % de 41 600) | chico                                             |

Por submódulo (`du_ooc_util_hier.rpt`): `u_dumper` 587 LUTs / 737 FFs, `u_cmd` 154 / 100, `u_loader` 93 / 130. El dumper es casi 2/3 de la DU: solo la copia de los latches son 648 FFs.

> `u_exec`, `u_resp` y `u_mux` no aparecen en esa tabla: son tan chicos que Vivado los **aplana** dentro del padre al optimizar. No desaparecieron: el log muestra que se sintetizaron, y la cuenta cierra (faltan 50 FFs en la tabla: 38 del exec + los del `resp_tx`).

**Conclusión de la primera mirada:** todo bien, salvo que 0,86 ns de margen es poco para lógica de control. Había que mirar **qué** camino era el peor.

---

## 3. Hallazgo 1: el camino crítico recalculaba algo que no cambia

### 3.1 Qué decía el reporte

`du_ooc_timing_setup.rpt`, el primero de la lista:

```text
Slack (MET) :     0.859ns
Source:           u_dumper/r_k_reg[5]/C
Destination:      u_dumper/r_xor_reg[6]/D
Data Path Delay:  9.088ns  (logic 4.294ns (47.3%)  route 4.794ns (52.7%))
Logic Levels:     12  (CARRY4=5 LUT3=2 LUT4=2 LUT6=3)
```

Cómo se lee:

- **Source / Destination:** el camino arranca en el flip-flop `r_k[5]` (K, cantidad de palabras de DMEM usadas) y termina en `r_xor[6]` (el checksum que se va calculando).
- **Logic Levels = 12:** el dato atraviesa 12 celdas en serie. **CARRY4** es la cadena de acarreo rápida de la FPGA, la que usa para **sumar y comparar**; 5 en serie es mucho.
- **logic 47 % / route 53 %:** casi la mitad del tiempo es lógica y la otra mitad cables.

Los 9 caminos siguientes eran **el mismo**: arrancaban en `r_k` y terminaban en los otros bits de `r_xor` o en `r_mem_addr`.

### 3.2 Seguirlo en el código

¿Qué tiene que ver K con el checksum? Siguiendo los cables en `du_dumper.v`:

```text
r_k ──► 4K + 2K ──► + 221 ──► mux r_modo ──► + 4 ──────────► ¿== r_pos? ──► mux o_tx_data ──► XOR ──► r_xor
        └────── w_len_snap ──────┘  (w_len)   (w_pos_checksum)
```

El dumper pregunta **en cada ciclo** "¿el byte que sale ahora es el checksum?" (`r_pos == w_pos_checksum`). Y `w_pos_checksum` se calculaba **en cada ciclo** a partir de K: tres sumas en fila. El resultado de la comparación elige qué byte sale (`o_tx_data`), y ese byte entra al XOR del checksum. Todo en un ciclo.

### 3.3 Por qué era evitable

K se copia en `r_k` **al pedido** y **no cambia en todo el volcado** (el núcleo está congelado). Un snapshot dura ~1 s, unos 100 millones de ciclos, y en cada uno el hardware rehacía la misma cuenta con el mismo resultado. Y como esa cuenta estaba **en el medio** del camino hacia `r_xor`, cada ciclo tenía que esperarla.

Es el equivalente en hardware de esto en software:

```c
for (pos = 0; ...; pos++)
    if (pos == 221 + 6*k + 4) ...   // se recalcula en cada vuelta, pero k no cambia
```

Con una diferencia importante: en software el compilador suele sacar esa cuenta del lazo solo (_loop-invariant code motion_). En hardware **nadie lo hace por vos**: lo que escribís en un `assign` es un circuito que está ahí siempre, y si cae en un camino largo, lo alarga.

---

## 4. El cambio: calcular una vez y guardar en un registro

### 4.1 La idea

Calcular la longitud **una sola vez, en el ciclo del pedido**, y guardarla en un **registro**. Desde ahí, el camino de cada byte queda corto:

```text
antes:  r_k ──► sumas (5 CARRY4) ──► ¿== r_pos? ──► mux ──► XOR ──► r_xor
después:                     r_pos ──► ¿== r_pos_checksum? ──► mux ──► XOR ──► r_xor
```

Las sumas siguen existiendo, pero en un camino aparte que **termina en el registro** (entrada → sumas → `r_pos_checksum`). Ya no se encadenan con la comparación, el mux y el XOR.

Esta es una técnica general: **sacar del camino crítico lo que es constante durante una operación** y precalcularlo en un registro. Cuesta flip-flops (que en una FPGA sobran) y gana tiempo.

### 4.2 Trampa 1: hacían falta dos registros, no uno

Antes de cambiar, hay que mirar **todos** los lugares donde se usa la cuenta lenta:

| Dónde se usaba                                                                    | Qué usaba                    |
| --------------------------------------------------------------------------------- | ---------------------------- |
| "¿es el checksum?" (la tabla de `o_tx_data`, `w_suma_xor`, `w_en_mem`, `ESPERAR`) | `w_pos_checksum = w_len + 4` |
| bytes 2 y 3 de la trama (la longitud)                                             | **`w_len`** directo          |

Si se registraba solo la posición del checksum, el camino `r_k → sumas → w_len → o_tx_data → XOR → r_xor` **seguía existiendo** por los bytes de longitud. Por eso son dos registros:

- `r_len`: la longitud del payload (bytes 2 y 3);
- `r_pos_checksum`: `r_len + 4`, la posición del checksum.

### 4.3 Trampa 2: cuándo se cargan

El primer byte de la trama es el `A5`, con `r_pos = 0`. La tabla de `o_tx_data` pregunta **primero** si `r_pos == r_pos_checksum`. Si el registro todavía tuviera un valor viejo (por ejemplo **0**, después de un reset), saldría el checksum en lugar del `A5`. Entonces los registros tienen que estar listos **antes** del primer byte: se cargan **en `IDLE`, en el mismo ciclo del pedido**.

### 4.4 Trampa 3: con qué se calculan

En ese mismo ciclo, `r_k` **todavía no** tiene el K nuevo: lo toma en ese flanco. Por eso la cuenta se hace con las **entradas** del pedido (`i_dbg_used_count`, `i_dm_n`), no con los registros:

```verilog
// Longitudes con las ENTRADAS del pedido
wire [15:0] w_k_in        = {{(15-DMEM_ADDR_BITS){1'b0}}, i_dbg_used_count};
wire [15:0] w_len_snap_in = LEN_FIJO + (w_k_in << 2) + (w_k_in << 1);   // 221 + 6K
wire [15:0] w_len_mem_in  = 16'd4 + (i_dm_n << 2);                       // 4 + 4n

// En IDLE, con i_req_dump:
r_len          <= w_len_snap_in;
r_pos_checksum <= w_len_snap_in + 16'd4;
// En IDLE, con i_req_dump_mem y el rango OK:
r_len          <= w_len_mem_in;
r_pos_checksum <= w_len_mem_in + 16'd4;
```

Y en el resto del módulo, `w_len` → `r_len` y `w_pos_checksum` → `r_pos_checksum`.

> **`6K` como `(K << 2) + (K << 1)`** y no `6 * K`: con desplazamientos son solo sumas. Un `*` podría llevar a Vivado a usar un DSP o un multiplicador hecho con LUTs.

### 4.5 Verificación funcional

Un cambio de timing **no tiene que cambiar el comportamiento**. Antes de volver a Vivado: `make lint` limpio y `make sim-all` 13 de 13. `tb_du_dumper` y `tb_du_dump_mem` comparan longitud y checksum de cada trama, así que cualquiera de las tres trampas los hace fallar.

---

## 5. Segunda corrida: antes y después

|                        |           Antes |         Después | Cambio                                 |
| ---------------------- | --------------: | --------------: | -------------------------------------- |
| **WNS (setup)**        |        0,859 ns |    **1,873 ns** | **+1,01 ns** de margen (más del doble) |
| WHS (hold)             |        0,100 ns |        0,149 ns | igual (hold no era problema)           |
| Peor camino arranca en |        `r_k[5]` |      `r_pos[1]` | las sumas de K salieron                |
| Logic Levels           |              12 |           **7** | −5                                     |
| CARRY4 en el camino    |               5 |           **1** | −4                                     |
| Data Path Delay        |        9,088 ns |        8,120 ns | −0,97 ns                               |
| … de lógica            | 4,294 ns (47 %) | 1,974 ns (24 %) | **−2,3 ns**                            |
| … de ruteo             | 4,794 ns (53 %) | 6,146 ns (76 %) | +1,35 ns (ver §6)                      |
| Flip-flops             |            1017 |            1049 | **+32** = `r_len` + `r_pos_checksum`   |
| LUTs                   |             865 |             889 | +24                                    |
| Latches                |               0 |               0 | —                                      |

**Lectura:** la lógica del peor camino bajó a menos de la mitad, a cambio de 32 flip-flops (0,08 % de la FPGA). Un buen negocio.

Una frecuencia orientativa: con WNS = 1,873 ns, el peor camino necesita unos 10 − 1,873 ≈ 8,1 ns, o sea que la DU sola andaría hasta ~120 MHz. Es una estimación de este bloque aislado, no del diseño final (ver §8).

---

## 6. Hallazgo 2: ahora manda el ruteo

El nuevo peor camino:

```text
Source:       u_dumper/r_pos_reg[1]/C
Destination:  u_dumper/r_xor_reg[7]/D
Data Path Delay:  8.120ns  (logic 1.974ns (24.3%)  route 6.146ns (75.7%))
Logic Levels:     7  (CARRY4=1 LUT3=1 LUT4=1 LUT5=2 LUT6=2)

r_pos[1] ─► CARRY4 ─(net fo=201, 1.863 ns)─► LUT3 ─► LUT5 ─► LUT5 ─► LUT6 ─► LUT6 ─► LUT4 ─► r_xor[7]
            w_off = r_pos − 4                 └──── tabla de o_tx_data (mux) ────┘    XOR
```

Ese es el camino **esperado** para un serializador: `r_pos` → posición en el payload → la tabla que elige el byte → el XOR del checksum. Ya no hay cuentas que no hacían falta.

Dos cosas para aprender de este reporte:

1. **`fo=201` (_fanout_ 201).** Un bit de `w_off` (`r_pos − 4`) alimenta 201 entradas de LUT: todas las comparaciones y restas de la tabla dependen de la posición. Un cable con tanto fanout es largo y lento: solo ese tramo son 1,86 ns, más que tres LUTs juntas.
2. **Cuando se achica la lógica, el ruteo pasa a dominar** (76 %). Las celdas del camino quedaron repartidas en el chip (de `SLICE_X9Y41` a `SLICE_X3Y56` y de vuelta a `SLICE_X8Y44`). A partir de acá, ganar más tiempo no pasa por "menos lógica" sino por "menos fanout" o "cortar el camino con un registro".

**¿Hay que hacer algo más?** Hoy no: 1,87 ns de margen alcanza. Si hiciera falta (por ejemplo, al juntar con el núcleo), la siguiente mejora sería **registrar el byte de salida**: calcularlo en `BUSCAR`, que siempre precede a `ENVIAR`, y guardarlo. El camino largo se partiría en dos de un ciclo cada uno. Está anotado en la guía de la DU (§38).

### 6.1 Un camino que cruza módulos

El 4.° de la lista es distinto:

```text
Source:       u_cmd/r_dm_args_reg[20]/C        (argumentos de DUMP_MEM, en du_cmd_fsm)
Destination:  u_dumper/r_xor_reg[1]/CE         (clock enable del checksum, en du_dumper)
Logic Levels: 9  (CARRY4=3 ...)                 slack 2.163 ns
```

Es la **validación de `DUMP_MEM`**: los argumentos que guarda `u_cmd` entran al dumper, pasan por la suma de 17 bits (`dir/4 + n ≤ 256`, las 3 CARRY4), deciden si el pedido arranca y terminan en el _enable_ de `r_xor`. Muestra que **los caminos no respetan los módulos**: para el timing, la jerarquía no existe, solo flip-flops y lógica entre ellos. Si algún día fuera el peor, se registraría `w_dm_ok` (validar un ciclo antes de arrancar).

---

## 7. Hallazgo 3: los warnings

| Warning                                                      | Cuántos | Qué significa                                                                                                                                                                                 | ¿Hay que hacer algo?                                                             |
| ------------------------------------------------------------ | ------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `Synth 8-6014` `o_flush_all_reg` y `o_load_done_reg` removed |       2 | En `du_loader`, `o_flush_all`, `o_clear_used` y `o_load_done` se ponen en 1 **siempre juntos** (estado `FIN`): son tres flip-flops idénticos. Vivado deja uno y lo conecta a las tres salidas | No. Es una optimización correcta. Si molesta, se puede escribir un solo registro |
| `Route 35-198` `HD.PARTPIN_LOCS`                             |     100 | En OOC los puertos no tienen lugar en el chip, así que no se enrutan hasta el borde                                                                                                           | No: normal en OOC                                                                |
| `Route 35-197`, `Timing 38-242` `HD.CLK_SRC`                 |       2 | Vivado no sabe de dónde viene el reloj, así que **no estima el skew**                                                                                                                         | No, pero los números son algo optimistas (§8)                                    |
| `DRC 23-814`, `Constraints 18-8777`                          |       4 | Chequeos que solo se pueden hacer con el diseño completo                                                                                                                                      | No                                                                               |
| `Vivado 12-1348` "No Latch(s) found"                         |       1 | Lo genera el script al buscar latches; que no haya es lo que queremos                                                                                                                         | No                                                                               |

Y un INFO: `default block is never used` en `du_exec_ctrl`. Con el estado `DRAIN` (US-407) los 4 códigos de 2 bits están usados, así que el `default` del `case` nunca se alcanza. Es correcto.

**Lección:** no todos los warnings son problemas, pero **todos se leen**. El de los registros duplicados, por ejemplo, revela algo del diseño (tres salidas que siempre valen lo mismo) que no se veía en el código.

---

## 8. Lo que estos números NO dicen

1. **El camino a través del núcleo no se midió.** El byte del snapshot sale de `r_pos` → `o_dbg_reg_addr` → **banco de registros del núcleo** → `i_dbg_reg_data` → `o_tx_data` → UART, en un ciclo. En OOC los caminos que entran o salen por puertos **no tienen restricción**, así que Vivado no los analiza. Ese camino recién existe en el diseño completo (US-401 / US-411).
2. **El skew del reloj no está estimado** (warning `HD.CLK_SRC`). Con el diseño completo, el margen va a ser un poco menor.
3. **La ubicación va a cambiar.** Con el núcleo al lado, Vivado ubica todo distinto, y el ruteo (que ahora es el 76 % del peor camino) puede mejorar o empeorar.

Por eso la verificación de timing que vale es la del diseño completo (US-601/602). Esta sirvió para encontrar problemas **temprano**, cuando el código de la DU está fresco y el cambio es chico.
