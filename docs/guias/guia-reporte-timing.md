# Mini guía: cómo leer el reporte de timing de Vivado

Guía corta para abrir el **Timing Summary** de Vivado y saber en un minuto si el diseño cumple, por qué y cuánto margen tiene. Los criterios del proyecto (WNS ≥ 0,3 ns, WHS ≥ 0) están en ADR-016 y NFR-1 del PRD.

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
