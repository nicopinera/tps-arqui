# Guía de timing: el reporte de Vivado, camino crítico, skew y Clock Wizard

La **parte 1** (secciones 1 a 8) es una guía corta para abrir el **Timing Summary** de Vivado y saber en un minuto si el diseño cumple, por qué y cuánto margen tiene. La **parte 2** (secciones 9 a 16) desarrolla los conceptos: las cuentas de setup y hold, el camino crítico, el skew, el jitter, la frecuencia máxima, el Clock Wizard (MMCM) y la sincronización de señales externas, cada uno con el ejemplo real del sistema del TP3 (`hw/reports/top_*.rpt`, 85 MHz). Los criterios del proyecto (WNS ≥ 0,3 ns, WHS ≥ 0) están en ADR-016 y NFR-1 del PRD.

Para correr los análisis: [guia-sintesis-sistema.md](guia-sintesis-sistema.md). Un caso resuelto paso a paso: [guia-caso-timing-debug-unit.md](guia-caso-timing-debug-unit.md).

## 1. La idea: todo es un camino entre dos flip-flops

Un circuito sincrónico siempre tiene la misma forma. Un flip-flop **lanza** un dato en un flanco de reloj, el dato cruza lógica combinacional (sumadores, comparadores, muxes, cables) y otro flip-flop lo **captura** en el flanco siguiente:

```text
FF origen ──► [ lógica combinacional + cables ] ──► FF destino
   ▲ flanco t = 0                                      ▲ flanco t = T (10 ns a 100 MHz)
```

Vivado analiza **cada** camino y se hace dos preguntas:

1. **Setup:** ¿el dato llega **antes** del flanco que lo captura?
2. **Hold:** ¿el dato nuevo **no llega tan rápido** que pisa al viejo justo cuando se está capturando?

```text
reloj del FF destino   ____|‾‾‾‾‾‾‾‾|________|‾‾‾‾‾‾‾‾|____
                                             ▲ flanco de captura
                                    |<-setup->|<-hold->|
el dato tiene que estar estable     ##########|########     ← ventana prohibida para cambios
```

**Slack** (holgura) es el margen que sobra respecto del límite:

- **positivo** = cumple, con ese margen;
- **negativo** = falla, y el circuito puede capturar basura.

## 2. Dónde está el reporte

- **En la GUI:** `Open Implemented Design` → `Report Timing Summary`.
- **En Tcl:** `report_timing_summary -file hw/reports/timing_summary.rpt`.

**Que sea el de implementación, no el de síntesis.** El de síntesis **estima** los retardos de los cables; el de implementación usa el ruteo real. El que vale para el proyecto, y el que se guarda en `hw/reports/`, es el de implementación.

## 3. Las tres columnas del resumen

| Columna         | Sigla                                | Qué significa                                                  | Cumple si |
| --------------- | ------------------------------------ | -------------------------------------------------------------- | --------- |
| **Setup**       | **WNS** (_Worst Negative Slack_)     | margen del camino **más lento** de todo el diseño              | ≥ 0       |
|                 | **TNS** (_Total Negative Slack_)     | suma de todos los slacks negativos                             | = 0       |
|                 | Failing / Total Endpoints            | destinos que llegan tarde / destinos analizados                | 0 fallan  |
| **Hold**        | **WHS** (_Worst Hold Slack_)         | margen del camino **más rápido**                               | ≥ 0       |
|                 | **THS** (_Total Hold Slack_)         | suma de los slacks de hold negativos                           | = 0       |
| **Pulse Width** | **WPWS** (_Worst Pulse Width Slack_) | ¿el pulso del reloj es lo bastante ancho para FF, BRAM y MMCM? | ≥ 0       |

Debajo aparece la frase **"All user specified timing constraints are met"**: todo lo que se le **pidió** a Vivado se cumple. Ojo: esa frase no cubre lo que no se pidió (sección 5).

## 4. Ejemplo real: el top de US-401 a 100 MHz

| Dato            | Valor    | Lectura                                                                    |
| --------------- | -------- | -------------------------------------------------------------------------- |
| WNS             | 5,360 ns | el camino más lento llega 5,36 ns antes de que termine el ciclo de 10 ns   |
| TNS             | 0        | ningún camino falla setup                                                  |
| Total Endpoints | 99       | entradas de flip-flops analizadas (contadores, shift registers, FSM, LED…) |
| WHS             | 0,045 ns | el camino más rápido respeta el hold con 45 ps de margen                   |
| WPWS            | 4,5 ns   | cada mitad del ciclo (5 ns) sobra para los flip-flops                      |

**Frecuencia máxima aproximada.** El camino más lento tarda `T − WNS`:

```text
retardo ≈ 10 ns − 5,36 ns = 4,64 ns   →   f_max ≈ 1 / 4,64 ns ≈ 215 MHz
```

Es una estimación: a otra frecuencia Vivado rutea distinto. Para saberlo de verdad hay que implementar a esa frecuencia (US-602).

**Un WHS chico es normal.** El hold no depende de la frecuencia: Vivado lo arregla agregando retardo en el ruteo y suele dejar márgenes chicos y positivos. Un caso típico de camino rápido es `r_rx_meta` → `r_rx_sync` (un FF directo a otro, sin lógica). Lo que importa es el **signo**, no el tamaño.

## 5. Lo que el resumen no dice: Check Timing y User Ignored Paths

Vivado solo analiza los caminos que tienen restricción. Un puerto sin restricción **no aparece como falla: directamente no se analiza**. Para eso están dos secciones del árbol de la izquierda:

**Check Timing**, con los avisos de lo que quedó sin restricción:

| Aviso                              | Qué significa                 | En este proyecto                                                            |
| ---------------------------------- | ----------------------------- | --------------------------------------------------------------------------- |
| `no_input_delay`                   | entrada sin `set_input_delay` | aceptable para `i_reset`; **`rx` no tiene que aparecer** (tiene false path) |
| `no_output_delay`                  | salida sin `set_output_delay` | aceptable para `tx` y los LEDs: las lee un humano o un chip a 19200 bps     |
| `no_clock`                         | un FF sin reloj definido      | **nunca** debería aparecer: falta un `create_clock`                         |
| `unconstrained_internal_endpoints` | caminos internos sin analizar | revisar siempre                                                             |

**User Ignored Paths** muestra los caminos que se excluyeron a propósito. Ahí tiene que figurar el que sale de `rx`: es la prueba de que Vivado leyó el `set_false_path -from [get_ports rx]` del `.xdc`. ¿Por qué ese false path? `rx` es asíncrono (llega de la PC sin relación con nuestro reloj) y lo sincronizan dos flip-flops con `ASYNC_REG`. Analizarlo con el reloj no tiene sentido.

## 6. Si algo falla: leer el peor camino

Doble clic en el WNS (o el WHS) del resumen, o en Tcl `report_timing -max_paths 10 -sort_by slack` (setup) y `-delay_type min` (hold). Por cada camino hay que mirar:

| Campo                | Qué mirar                                                                  |
| -------------------- | -------------------------------------------------------------------------- |
| Source / Destination | de qué registro a qué registro va: te dice **qué parte del RTL** es lenta  |
| Data Path Delay      | retardo total, separado en **logic** (compuertas) y **route** (cables)     |
| Logic Levels         | cuántas LUT atraviesa en serie: más niveles = más lento                    |
| Clock Skew           | diferencia de llegada del reloj entre origen y destino (normalmente chica) |

Cómo interpretarlo:

| Si…                                      | Probablemente…                                                      | Se arregla con…                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| setup falla y **logic** domina           | demasiada lógica en un ciclo (sumador + comparador + mux)           | partir el camino con un registro (_pipelining_) o simplificar la lógica           |
| setup falla y **route** domina           | cables largos, diseño disperso o _fanout_ alto                      | duplicar el registro de alto _fanout_, revisar constraints                        |
| hold falla                               | casi siempre un problema de **reloj** (skew, dos relojes mezclados) | revisar `create_clock` y los cruces de reloj; no se arregla bajando la frecuencia |
| el camino empieza o termina en un puerto | falta o sobra una restricción de E/S                                | `set_input_delay`, `set_output_delay` o `set_false_path`                          |

## 7. Checklist de 30 segundos

1. ¿Es el reporte de **implementación**?
2. ¿**WNS ≥ 0**? El proyecto pide **≥ 0,3 ns** de margen (ADR-016).
3. ¿**WHS ≥ 0**?
4. ¿**TNS = 0**, **THS = 0** y Failing Endpoints = 0?
5. ¿**Check Timing** solo muestra los avisos esperados, sin `no_clock` y sin `rx`?
6. ¿**User Ignored Paths** muestra el camino de `rx`?
7. Guardar el `.rpt` en `hw/reports/` y anotar WNS/WHS en la tabla de timing (ADR-016).

## 8. Errores comunes

- **Pensar que un WNS grande es malo.** Es al revés: más grande es más margen.
- **Asustarse con un WHS chico.** Importa el signo; 0,045 ns positivo está bien.
- **Creer que "constraints met" significa que el diseño anda.** Solo cubre los caminos **restringidos**. Lo que no tiene restricción no se analiza y no aparece como falla: por eso existe Check Timing.
- **Mirar el reporte de síntesis.** Los cables están estimados; el número que vale es el de implementación.
- **Tratar de arreglar un hold bajando la frecuencia.** El hold no depende del período; un hold negativo apunta al reloj, no a la velocidad.
- **Confundir slack con retardo.** El slack es lo que **sobra**; el retardo del camino es `T − slack` (para setup).

---

# Parte 2 — Conceptos de timing a fondo

## 9. Las cuentas de setup y de hold

### 9.1 Vocabulario

| Término                                   | Qué es                                                                                                |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Flanco de lanzamiento** (_launch edge_) | El flanco en el que el FF origen saca el dato nuevo                                                   |
| **Flanco de captura** (_capture edge_)    | El flanco en el que el FF destino lo guarda: un período después para setup, el mismo flanco para hold |
| **t_cq** (_clock-to-Q_)                   | Lo que tarda el FF origen en mostrar el dato en `Q` después del flanco                                |
| **t_setup**                               | Cuánto antes del flanco tiene que estar estable el dato en `D` del FF destino                         |
| **t_hold**                                | Cuánto después del flanco tiene que seguir estable                                                    |
| **Arrival time**                          | Cuándo llega de verdad el dato a `D`: reloj hasta el origen + t_cq + lógica + cables                  |
| **Required time**                         | Hasta cuándo puede llegar (setup) o desde cuándo (hold), según el reloj del destino                   |
| **Slack**                                 | Setup: `required − arrival`. Hold: `arrival − required`. En los dos, positivo = cumple                |
| **Clock path delay**                      | Lo que tarda el reloj desde el pin de la placa hasta un FF (IBUF → MMCM → BUFG → árbol del reloj)     |

### 9.2 Setup: el dato tiene que llegar a tiempo

La condición, escrita a mano:

```text
t_reloj_origen + t_cq + t_lógica + t_ruteo  ≤  T + t_reloj_destino − t_setup − incertidumbre
└──────────────── arrival ───────────────┘     └──────────────────── required ────────────────────┘
```

Si el reloj llega **más tarde** al destino que al origen (`t_reloj_destino > t_reloj_origen`), el destino captura más tarde y el dato tiene **más** tiempo. Esa diferencia es el **skew** (sección 11).

**Ejemplo real** (peor camino de setup a 85 MHz, `top_timing_setup.rpt`, T = 11,765 ns):

| Paso                                                   | Valor (ns) | De dónde sale                                                          |
| ------------------------------------------------------ | ---------- | ---------------------------------------------------------------------- |
| Reloj hasta el FF origen `u_dumper/r_pos_reg[3]` (SCD) | −0,959     | IBUF + MMCM + BUFG + árbol (el MMCM "adelanta" el reloj, sección 13.4) |
| + camino de datos (t_cq + 15 niveles + cables)         | +11,226    | lógica 4,253 + ruteo 6,973                                             |
| **= arrival time**                                     | **10,267** |                                                                        |
| Flanco de captura                                      | 11,765     | un período después                                                     |
| + reloj hasta el FF destino `u_tx/o_p_reg` (DCD)       | −1,561     |                                                                        |
| + clock pessimism removal (CPR)                        | +0,491     | sección 11.3                                                           |
| − clock uncertainty                                    | −0,113     | jitter, sección 12                                                     |
| − t_setup del FDRE                                     | +0,031     | en este FF el setup es levemente negativo                              |
| **= required time**                                    | **10,612** |                                                                        |
| **Slack = 10,612 − 10,267**                            | **+0,345** | cumple, y supera el margen de 0,3 ns de ADR-016                        |

### 9.3 Hold: el dato nuevo no puede llegar demasiado rápido

```text
t_reloj_origen + t_cq + t_lógica + t_ruteo  ≥  t_reloj_destino + t_hold
```

Acá se compara contra el **mismo** flanco: el FF destino está capturando el dato viejo, y el nuevo, que salió del origen en ese mismo flanco, no puede pisarlo. Por eso **el período T no aparece** y bajar la frecuencia no arregla un hold.

**Ejemplo real** (peor hold, `top_timing_hold.rpt`): `u_core/u_mem_wb_reg/o_pc_plus4_reg[8]` → `u_du/u_dumper/r_latches_reg[576]`, el registro del latch MEM/WB que la Debug Unit copia para el snapshot.

| Paso                                    | Valor (ns) |
| --------------------------------------- | ---------- |
| Reloj hasta el origen (SCD)             | −0,619     |
| + t_cq + un cable (0 niveles de lógica) | +0,387     |
| **= arrival**                           | **−0,232** |
| Reloj hasta el destino (DCD)            | −0,859     |
| + CPR                                   | +0,503     |
| + t_hold                                | +0,070     |
| **= required**                          | **−0,286** |
| **Slack = arrival − required**          | **+0,054** |

El camino es un cable solo entre dos FF. Cumple porque el dato tarda 0,387 ns y el reloj llega 0,264 ns más tarde al destino: skew positivo (sección 11).

### 9.4 Corners: lento para setup, rápido para hold

Vivado analiza cada camino en dos condiciones extremas del chip (_process corners_):

- **Slow** (transistores lentos, temperatura alta) para setup, porque ahí los caminos tardan más.
- **Fast** para hold, porque ahí los datos llegan antes.

Por eso el reporte dice `Setup (Max at Slow Process Corner)` y `Hold (Min at Fast Process Corner)`, y un mismo cable tiene retardos distintos en cada reporte.

## 10. El camino crítico

### 10.1 Concepto

El **camino crítico** es el camino entre dos flip-flops con **menos slack**: el que limita la frecuencia. No es "el más largo en el código" sino el más lento **después de ubicar y rutear**, así que puede incluir cables largos aunque tenga poca lógica.

### 10.2 Cómo se encuentra

1. `report_timing -max_paths 10 -sort_by slack`: lo hace `impl_top.tcl` y lo resume `make reportes`.
2. Mirar **origen y destino**: dicen qué parte del RTL es.
3. Mirar los **tramos**: qué celdas atraviesa (CARRY4 = sumador, RAMD64E = LUTRAM, MUXF7 = mux grande) y qué redes tienen _fanout_ alto.

### 10.3 El del TP3

| Caso                                  | Peor camino                                                                                               | Slack     |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------- | --------- |
| 100 MHz, sin MMCM                     | `u_dumper/r_pos` → 2 sumas → lectura de la DMEM por el puerto de depuración → `r_xor` (checksum) → `u_tx` | −1,316 ns |
| 85 MHz, diseño final                  | el mismo camino                                                                                           | +0,345 ns |
| 85 MHz, primer camino del núcleo (#4) | `EX/MEM.rd` → Forwarding Unit → `branch_cmp` → redirección / stall → enable del PC                        | +0,664 ns |

Qué se aprende de cada uno:

- **Debug Unit:** en un mismo ciclo calcula la dirección (`base + offset`), lee la LUTRAM (combinacional, ADR-005), elige el byte, actualiza el XOR y deja el resultado en la UART. El 62 % del retardo es **ruteo**: la DMEM está en el núcleo y el dumper en la Debug Unit, así que el dato cruza el chip de ida y de vuelta. La red de la dirección tiene _fanout_ de 16 a 50, porque va a todas las LUTRAM de la DMEM.
- **Núcleo:** es el camino que anticipaba ADR-006. El forwarding alimenta la comparación del branch, y esa comparación decide el próximo PC en el mismo ciclo.

Esto solo se ve **en contexto**. Los análisis fuera de contexto (OOC) del núcleo y de la Debug Unit, cada uno por separado, no ven el camino que cruza de uno al otro.

### 10.4 Cómo se acorta un camino

| Técnica                      | Idea                                                                                    | En este proyecto                                                                                            |
| ---------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Registrar** (_pipelining_) | Partir el camino con un FF: dos ciclos cortos en lugar de uno largo                     | Candidato: registrar la lectura de la DMEM en el dumper (cuesta un ciclo por byte, irrelevante a 19200 bps) |
| **Precalcular**              | Sacar del camino lo que no cambia en cada ciclo                                         | `du_dumper` ya calcula la longitud y la posición del checksum una sola vez                                  |
| **Replicar registros**       | Copiar un FF de _fanout_ alto para que cada copia maneje menos cargas y quede más cerca | Vivado lo hace solo: `r_pos_reg[2]_replica` en el reporte de 100 MHz                                        |
| **Bajar la frecuencia**      | Más período para el mismo camino                                                        | Es lo que se hizo: 85 MHz con el MMCM (ADR-016)                                                             |

## 11. Skew

### 11.1 Concepto

El **clock skew** es la **diferencia de llegada de un mismo flanco de reloj** a dos flip-flops distintos:

```text
skew = t_reloj_destino − t_reloj_origen
```

Lo produce la **red de distribución del reloj**, porque el reloj recorre cables de distinto largo hasta cada FF. **No lo produce un camino de datos.** Por eso la respuesta a "¿este camino crítico genera skew?" es **no**: el camino crítico _sufre_ el skew, que le suma o le resta margen, pero no lo genera.

### 11.2 Signo y consecuencias

| Skew                                              | En setup                            | En hold                                           |
| ------------------------------------------------- | ----------------------------------- | ------------------------------------------------- |
| **Positivo** (el destino recibe el reloj después) | Ayuda: el destino captura más tarde | **Perjudica**: el dato nuevo puede pisar al viejo |
| **Negativo** (el destino recibe el reloj antes)   | Perjudica: le quita tiempo al dato  | Ayuda                                             |

Valores reales a 85 MHz:

| Camino                               | Skew             | Efecto                                                                         |
| ------------------------------------ | ---------------- | ------------------------------------------------------------------------------ |
| Peor setup (Debug Unit → UART)       | −0,111 ns        | Le quita 0,1 ns a un período de 11,8 ns: menos del 1 %                         |
| Primeros caminos de setup del núcleo | −0,23 a −0,29 ns | Igual de chico; ninguno falla                                                  |
| Peor hold (latch MEM/WB → dumper)    | +0,264 ns        | El que más importa: el camino es un cable solo y aun así cumple (slack +0,054) |

### 11.3 Clock Pessimism Removal (CPR)

Origen y destino comparten parte del camino del reloj (IBUF → MMCM → BUFG). Para ser pesimista, Vivado calcula ese tramo con un retardo para el origen y con otro para el destino (máximo y mínimo). Pero un mismo cable no puede tener dos retardos a la vez en el mismo flanco. El **CPR** devuelve esa diferencia del tramo común. En el reporte: `Clock Path Skew = DCD − SCD + CPR`.

### 11.4 Por qué acá el skew es chico

- **Un solo reloj por una sola red global** (BUFG): el árbol de reloj de la FPGA está diseñado para llegar casi al mismo tiempo a todo el chip.
- **Nada de lógica en el reloj** (ADR-001): el paso a paso usa _clock enable_, no una compuerta en el reloj.

**Contraejemplo, el _clock gating_:** si el paso a paso se hubiera hecho con `assign clk_core = clock & step;`, el reloj del núcleo pasaría por una LUT y un cable común, y llegaría al núcleo **nanosegundos** después que a la Debug Unit. Todos los caminos Debug Unit → núcleo tendrían un skew positivo enorme (fallas de hold), y la compuerta podría generar _glitches_ (pulsos de reloj espurios). Es lo que el enunciado prohíbe cuando dice que "el clock no debe verse intervenido".

## 12. Jitter e incertidumbre del reloj

**Jitter:** el flanco del reloj no llega siempre exactamente al mismo momento; varía de un ciclo a otro. El oscilador de la placa tiene un poco (_system jitter_) y el MMCM agrega el suyo (_discrete jitter_), porque genera el reloj con un oscilador interno.

Vivado lo descuenta de cada camino como **clock uncertainty**:

```text
uncertainty = √(TSJ² + DJ²) / 2 + PE = √(0,071² + 0,215²) / 2 + 0 = 0,113 ns
```

Sin MMCM, con el reloj de la placa directo, la incertidumbre es más chica (solo TSJ). Es parte del costo del Clock Wizard: 0,1 ns menos de margen en cada camino.

## 13. Clock Wizard y MMCM

### 13.1 Concepto y problema que resuelve

La placa trae un oscilador fijo de **100 MHz** (pin W5). Si el diseño no cierra a 100 MHz, o si podría ir más rápido, hace falta **otra frecuencia**. Hay dos formas de conseguirla:

| Forma                                                               | Qué pasa                                                                                                                                                                                            |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Divisor con un contador: `always @(posedge clock) r_clk <= ~r_clk;` | El "reloj" sale de un FF y viaja por la red de datos, no por la del reloj. Da skew grande, Vivado no lo analiza bien y solo permite divisiones enteras (50; 33,3; 25 MHz…). **Prohibido** (ADR-016) |
| **MMCM** configurado con el Clock Wizard                            | Bloque dedicado del chip: genera casi cualquier frecuencia y la saca por la red global                                                                                                              |

### 13.2 Cómo funciona un MMCM

El **MMCM** (_Mixed-Mode Clock Manager_) es un **PLL** (_Phase-Locked Loop_) mejorado. Tiene un oscilador interno, el **VCO** (_Voltage-Controlled Oscillator_), que un lazo de realimentación ajusta hasta que queda enganchado en fase con el reloj de entrada:

```text
                 ┌───────────── realimentación (CLKFBOUT, ÷ M) ─────────────┐
                 ▼                                                          │
 clk_in1 ──► ÷ D ──► comparador de fase ──► VCO (f_vco) ──┬──────────────────┘
 (100 MHz)                                                └──► ÷ O ──► BUFG ──► clk_out1
```

```text
f_vco = f_in · M / D          f_out = f_vco / O
```

Para el TP3 (`make clk-wiz MHZ=85`), el Clock Wizard eligió:

```text
f_vco = 100 MHz · 40,375 / 4 = 1009,375 MHz      (rango válido del VCO en Artix-7 -1: 600 a 1200 MHz)
f_out = 1009,375 MHz / 11,875 = 85,000 MHz       (exacto)
```

En el MMCM, M y O pueden ser fraccionarios (en pasos de 1/8), a diferencia de un PLL simple; por eso salen 85 MHz exactos.

### 13.3 `locked` y el reset

Al encender la placa, el VCO tarda unos microsegundos en engancharse, y mientras tanto `clk_out1` no es confiable. El MMCM avisa con **`locked = 1`** cuando el reloj ya es estable. En `top.v`:

```verilog
r_rst_meta <= i_reset || !w_locked;   // reset hasta que el reloj esté estable
r_rst_sync <= r_rst_meta;             // segundo FF del sincronizador (sección 14)
```

### 13.4 El retardo "negativo" del MMCM

En el reporte, el MMCM aparece con un retardo de **−6,961 ns**. No viaja en el tiempo: con la realimentación, **compensa** los retardos del IBUF y del BUFG, de modo que el flanco que llega a los FF queda alineado con el flanco del pin, o incluso adelantado. Por eso el reloj llega a los FF en t ≈ −1 ns.

### 13.5 Restricciones: el reloj generado se deriva solo

El `.xdc` define solamente el reloj del pin:

```tcl
create_clock -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock]
```

Como Vivado conoce la configuración del MMCM, **deriva** el reloj de salida (`clk_out1_clk_wiz_0`, 11,765 ns) sin que haya que escribir nada.

Ojo: el `.xdc` que trae el IP **también** crea un reloj en `clk_in1`, que es el mismo pin. Si el `.xdc` de la placa usa `create_clock -add`, quedan **dos relojes primarios iguales** y Vivado analiza caminos "entre" ellos. Pasó en este proyecto. Se arregló sacando `-add`, así el reloj de la placa reemplaza al del IP.

### 13.6 Implementación en el proyecto

| Pieza                  | Dónde                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------- |
| Configuración del IP   | `hw/ip/clk_wiz_0/clk_wiz_0.xci` (lo único que se versiona, ADR-020), generado con `make clk-wiz MHZ=85` |
| Instancia              | `hw/rtl/top.v`, solo si está definida `SYNTHESIS` (Vivado) y no `SIN_MMCM`                              |
| Simulación             | Sin MMCM: el reloj del testbench entra directo (`w_clk = clock`, `w_locked = 1`)                        |
| Barrido de frecuencias | Sin MMCM (`-verilog_define SIN_MMCM`), cambiando el período del reloj del pin                           |
| Frecuencia en el RTL   | `CLK_FREQ_HZ = 85_000_000` en `top.v`: la UART calcula su divisor desde ahí (ADR-002)                   |

## 14. Señales externas: metaestabilidad y sincronizadores

**Concepto:** si la entrada `D` de un FF cambia justo dentro de la ventana de setup y hold, el FF puede quedar un rato en un valor intermedio antes de decidirse por 0 o 1. Eso es la **metaestabilidad**.

**Problema:** `rx` (la UART de la PC) y el botón de reset no tienen ninguna relación con nuestro reloj, así que tarde o temprano cambian en el peor momento.

**Solución:** dos flip-flops en cadena, un **sincronizador**. El primero puede quedar metaestable, pero tiene un ciclo entero para resolverse antes de que lo lea el segundo. Se marcan con `(* ASYNC_REG = "TRUE" *)` para que Vivado los ubique juntos.

**Restricción:** `set_false_path -from [get_ports rx]`. Un _false path_ le indica a Vivado que no analice ese camino: no tiene sentido medir el setup contra un reloj con el que la señal no tiene relación. El reset del botón pasa por el mismo esquema de 2 FF en `top.v`.

## 15. Frecuencia máxima y barrido

La estimación de la sección 4, `f_max ≈ 1 / (T − WNS)`, es solo una aproximación, porque **a otra frecuencia Vivado ubica y rutea distinto**: con mucho margen el placer no se esfuerza, y con poco margen sí. Por eso la frecuencia óptima se busca **implementando el diseño en cada frecuencia** (`make freq-sweep`):

| MHz | WNS (ns) | ¿Cumple ADR-016 (WNS ≥ 0,3)? |
| --- | -------- | ---------------------------- |
| 80  | 0,688    | sí                           |
| 85  | 0,324    | **sí: la óptima**            |
| 90  | 0,028    | no (cumple, pero sin margen) |
| 95  | −0,306   | no                           |
| 100 | −1,145   | no                           |

Con la estimación lineal, el WNS de 100 MHz (−1,145 ns) daría `f_max ≈ 1 / 11,145 ns ≈ 90 MHz`. El barrido confirma que a 90 MHz cumple justo, pero sin el margen pedido. Ese margen de 0,3 ns existe porque dos corridas parecidas pueden dar slacks distintos. Pasó en este proyecto: el diseño final con el MMCM dio 0,345 ns, y una corrida anterior, con el reloj duplicado, había dado 0,303 ns.

## 16. Más errores comunes de reloj

- **Dividir el reloj con un contador** y usar ese FF como reloj. En su lugar, usar un MMCM o un _clock enable_.
- **Poner lógica en el reloj** (_clock gating_): trae skew, glitches y holds rotos (sección 11.4).
- **Crear dos veces el mismo reloj** (`create_clock -add` sobre un pin que ya tiene reloj): aparecen caminos entre relojes que no existen (sección 13.5).
- **Olvidar `locked`:** el sistema arranca con un reloj inestable y los primeros ciclos hacen cualquier cosa.
- **Cambiar la frecuencia del MMCM sin cambiar `CLK_FREQ_HZ`:** la UART calcula mal el baud rate y recibe basura.
- **Leer `rx` sin sincronizador:** fallas esporádicas, imposibles de reproducir en simulación.
- **Decir que "el camino crítico genera skew":** el skew sale de la red del reloj; el camino solo lo sufre.
