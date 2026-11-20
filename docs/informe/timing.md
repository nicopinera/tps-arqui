# Análisis de timing del sistema (US-601, US-602)

Análisis del `top` completo (UART + Debug Unit + núcleo) **en contexto**: con los pines y el reloj reales de la Basys 3, después de implementar (`route_design`).

- **Datos:** salen de los reportes versionados en `TP3/hw/reports/`, resumidos por `make reportes` en [datos/reportes_vivado.md](datos/reportes_vivado.md) (85 MHz, diseño final) y en [datos/reportes_vivado_100mhz_directo.md](datos/reportes_vivado_100mhz_directo.md) (100 MHz sin MMCM, el "antes").
- **Conceptos** (setup, hold, skew, MMCM): [guia-reporte-timing.md](../guias/guia-reporte-timing.md).
- **Cómo se corre:** [guia-sintesis-sistema.md](../guias/guia-sintesis-sistema.md).

## 1. Resumen

| Corrida                           | Reloj                           | WNS (ns)   | TNS (ns) | Endpoints que fallan | WHS (ns) | Incertidumbre (ns) | ¿Cumple?                |
| --------------------------------- | ------------------------------- | ---------- | -------- | -------------------- | -------- | ------------------ | ----------------------- |
| **Antes:** 100 MHz, reloj directo | `sys_clk_pin`, 10 ns            | **−1,316** | −18,849  | 76 de 14 528         | 0,039    | 0,035              | No                      |
| **Después:** 85 MHz con MMCM      | `clk_out1_clk_wiz_0`, 11,765 ns | **+0,345** | 0        | 0 de 14 525          | 0,054    | 0,113              | Sí, con margen ≥ 0,3 ns |

El diseño no cierra a la frecuencia de la placa. Se aplicó el criterio de ADR-016 (barrido, sección 4) y el sistema final corre a **85 MHz** con un Clock Wizard.

## 2. Camino crítico

### 2.1 Los 10 peores caminos de setup (85 MHz)

| #   | Slack (ns) | Origen → destino                                              | Retardo (ns) | Lógica / ruteo | Niveles | Skew (ns) |
| --- | ---------- | ------------------------------------------------------------- | ------------ | -------------- | ------- | --------- |
| 1   | 0,345      | `u_du/u_dumper/r_pos_reg[3]` → `u_tx/…/o_p_reg`               | 11,226       | 38 % / 62 %    | 15      | −0,111    |
| 2   | 0,630      | `u_du/u_dumper/r_pos_reg[2]` → `u_tx/…/o_b_reg[2]`            | 10,940       | 40 % / 60 %    | 15      | −0,111    |
| 3   | 0,638      | `u_du/u_dumper/r_pos_reg[2]` → `u_du/u_dumper/r_xor[1]`       | 10,834       | 38 % / 62 %    | 13      | −0,113    |
| 4   | 0,664      | `u_core/u_ex_mem_reg/o_rd[2]` → `u_if_stage/r_pc[0]` (CE)     | 10,556       | 24 % / 76 %    | 12      | −0,227    |
| 5   | 0,673      | `u_core/u_ex_mem_reg/o_rd[2]` → `u_if_stage/r_pc[1]` (CE)     | 10,547       | 24 % / 76 %    | 12      | −0,227    |
| 6   | 0,673      | `u_core/u_ex_mem_reg/o_rd[2]` → `u_if_stage/r_pc[8]` (CE)     | 10,547       | 24 % / 76 %    | 12      | −0,227    |
| 7   | 0,684      | `u_du/u_dumper/r_pos_reg[2]` → `u_tx/…/o_b_reg[5]`            | 10,886       | 40 % / 60 %    | 15      | −0,112    |
| 8   | 0,734      | `u_core/u_ex_mem_reg/o_rd[2]` → `u_if_id_reg/o_instr[18]` (R) | 10,195       | 25 % / 75 %    | 12      | −0,294    |
| 9   | 0,752      | `u_core/u_ex_mem_reg/o_rd[2]` → `u_if_id_reg/o_instr[10]` (R) | 10,177       | 25 % / 75 %    | 12      | −0,294    |
| 10  | 0,752      | `u_core/u_ex_mem_reg/o_rd[2]` → `u_if_id_reg/o_instr[19]` (R) | 10,177       | 25 % / 75 %    | 12      | −0,294    |

Hay **dos familias** de caminos:

- **Debug Unit → UART** (1, 2, 3, 7): el armado del snapshot.
- **Núcleo, forwarding → control** (4 a 6, 8 a 10): de `EX/MEM.rd` al enable del PC (CE) o al flush de IF/ID (R).

### 2.2 El peor camino, etapa por etapa

**Camino:** `u_du/u_dumper/r_pos_reg[3]` → `u_tx/datapath/o_p_reg_reg`, con slack de +0,345 ns.

Tramos del reporte agrupados por función. Cada fila suma la lógica y los cables de ese tramo:

| #   | Tramo                               | Celdas                        | Retardo (ns) | Qué hace en el RTL                                                                      |
| --- | ----------------------------------- | ----------------------------- | ------------ | --------------------------------------------------------------------------------------- |
| 1   | Lanzamiento                         | FDRE (t_cq) + red (fanout 7)  | 0,980        | `r_pos`: qué byte del snapshot se está enviando                                         |
| 2   | Offset dentro de la zona de memoria | 2 × CARRY4 + red (fanout 26)  | 1,426        | `w_off = r_pos − inicio de la zona`                                                     |
| 3   | Dirección de la DMEM                | LUT2, LUT6, CARRY4 + redes    | 1,916        | `w_mem_addr_dm = base + w_off / 4`                                                      |
| 4   | Llegada a la LUTRAM                 | LUT3 + red (fanout 16)        | 1,060        | La dirección se reparte a todas las LUTRAM de la DMEM (puerto de lectura de depuración) |
| 5   | Lectura de la DMEM                  | RAMD64E + MUXF7 + red         | 1,079        | Lectura combinacional (ADR-005), de vuelta del núcleo a la Debug Unit                   |
| 6   | Selección del byte y checksum       | LUT5, LUT6, MUXF7, LUT6, LUT6 | 3,257        | Elegir el byte de la palabra (`w_mem_data`) y calcular `r_xor ^ byte`                   |
| 7   | Mux de respuesta hacia la UART      | LUT5, LUT6 + redes (fanout 3) | 1,506        | `du_tx_mux` / `du_resp_tx` eligen el byte que entra al transmisor                       |
|     | **Total del camino de datos**       | 15 niveles                    | **11,226**   | lógica 4,253 (38 %) · ruteo 6,973 (62 %)                                                |

**A qué parte del sistema corresponde.** No es el pipeline: es la **Debug Unit armando el snapshot**. En un mismo ciclo calcula la dirección, lee la DMEM del núcleo, elige el byte, actualiza el checksum y se lo pasa a la UART.

**Por qué es el más lento:**

- Tiene **mucho ruteo** (62 %), porque el dato sale de la Debug Unit, entra a la DMEM, que está ubicada con el núcleo, y vuelve.
- La dirección tiene **fanout alto**: 26 en el offset y 16 a 50 en la dirección, según la corrida, porque llega a todas las LUTRAM de la DMEM.

**Lo que no se ve fuera de contexto.** El análisis OOC de la Debug Unit sola (`du_ooc_*.rpt`) no podía verlo: la DMEM queda del otro lado del límite del módulo.

### 2.3 El camino crítico del núcleo

El primero del núcleo es el #4 (+0,664 ns): `EX/MEM.rd[2]` → Forwarding Unit (compara `rd` con `rs1`/`rs2` de EX) → mux de forwarding → `branch_cmp` (CARRY4) → Hazard Unit (decide redirección y stall) → enable de `r_pc`.

Es el camino que anticipaban ADR-006 y US-303: resolver el branch en EX con operandos reenviados encadena forwarding, comparación y selección del PC en un mismo ciclo. Fuera de contexto, a 100 MHz, el núcleo tenía WNS = +0,119 ns. En el sistema completo el mismo tipo de camino da −0,443 ns a 100 MHz, porque el placer tiene que repartir el chip con la Debug Unit y los cables se alargan (76 % de ruteo).

### 2.4 Los 10 peores caminos de hold (85 MHz)

| #   | Slack (ns) | Origen → destino                                                                     | Retardo (ns) | Skew (ns) |
| --- | ---------- | ------------------------------------------------------------------------------------ | ------------ | --------- |
| 1   | 0,054      | `u_core/u_mem_wb_reg/o_pc_plus4[8]` → `u_du/u_dumper/r_latches[576]`                 | 0,387        | 0,264     |
| 2   | 0,057      | `u_core/u_mem_wb_reg/o_alu_result[10]` → `u_du/u_dumper/r_latches[514]`              | 0,394        | 0,265     |
| 3   | 0,060      | `u_core/u_id_ex_reg/o_instr[24]` → `u_du/u_dumper/r_latches[344]`                    | 0,391        | 0,265     |
| 4   | 0,061      | `u_core/u_id_ex_reg/o_instr[17]` → `u_core/u_ex_mem_reg/o_instr[17]`                 | 0,400        | 0,264     |
| 5   | 0,062      | `u_core/u_ex_mem_reg/o_store_data[26]` → `u_du/u_dumper/r_latches[410]`              | 0,392        | 0,264     |
| 6–9 | 0,062      | `u_du/u_loader/o_imem_addr[0]` → `u_instr_mem` (dirección de escritura de la LUTRAM) | 0,643        | 0,271     |
| 10  | 0,063      | `u_core/u_id_ex_reg/o_pc[23]` → `u_du/u_dumper/r_latches[127]`                       | 0,264        | 0,184     |

Todos son caminos **sin lógica** (0 niveles): un registro copiado directo en otro. Por ejemplo, la Debug Unit copia los latches del pipeline para el snapshot, o el loader escribe la IMEM. Son los más rápidos del diseño, y por eso los que más dependen del skew. Todos cumplen.

## 3. Skew

### 3.1 ¿Este camino crítico genera skew?

**No.** El camino crítico es un retardo de **datos** entre dos flip-flops. El skew es la diferencia de llegada del **reloj** a esos dos flip-flops, y lo genera la red de distribución del reloj, no la lógica que hay entre ellos (PRD §14, E4). Lo que sí pasa es que el skew **afecta** al margen del camino.

### 3.2 Valores medidos

| Caminos                            | Skew a 100 MHz, sin MMCM | Skew a 85 MHz, con MMCM | Efecto                                            |
| ---------------------------------- | ------------------------ | ----------------------- | ------------------------------------------------- |
| Peor setup (Debug Unit → UART)     | −0,034 ns                | −0,111 ns               | Le resta ese tiempo al camino: < 1 % del período  |
| Setup del núcleo (forwarding → PC) | −0,047 ns                | −0,227 a −0,294 ns      | Igual de chico frente a 11,8 ns                   |
| Peor hold (latches → dumper)       | +0,266 ns                | +0,264 ns               | Juega en contra del hold; aun así WHS = +0,054 ns |

### 3.3 Por qué es chico

Todo el sistema usa **un único reloj** distribuido por **una red global** (un BUFG que alimenta los 3663 elementos sincrónicos), **sin lógica intercalada** en el camino del reloj. El paso a paso se hace con _clock enable_ (ADR-001), no apagando el reloj.

El skew de setup crece un poco con el MMCM porque Vivado calcula el retardo del reloj con más dispersión entre el mínimo y el máximo. Sigue siendo una fracción mínima del período.

### 3.4 Consecuencias

- **Setup:** el skew negativo resta como mucho 0,3 ns de margen. Ya está incluido en el slack de cada camino, y todos cumplen.
- **Hold:** el skew positivo de unos 0,27 ns es la razón de que los caminos de hold tengan slacks chicos (0,05 ns). Vivado lo compensa con el retardo del cable; ninguno falla.
- **Qué habría pasado con _clock gating_:** una compuerta en el reloj del núcleo (por ejemplo, `clock & step` para el paso a paso) lo retrasaría nanosegundos respecto del de la Debug Unit. Los caminos de hold de la tabla 2.4, que cruzan entre los dos, fallarían por varios nanosegundos, y además la compuerta podría generar glitches. Por eso el enunciado prohíbe intervenir el reloj.

## 4. Frecuencia óptima (US-602)

### 4.1 Barrido

`make freq-sweep` sintetiza el sistema **sin MMCM** (macro `SIN_MMCM`) y lo implementa a cada frecuencia ([freq_sweep.csv](../../TP3/hw/reports/freq_sweep.csv)):

| MHz | Período (ns) | WNS (ns) | WHS (ns) | TNS (ns) | ¿Cumple ADR-016? (WNS ≥ 0,3 y WHS ≥ 0) |
| --- | ------------ | -------- | -------- | -------- | -------------------------------------- |
| 50  | 20,000       | 4,760    | 0,057    | 0        | sí                                     |
| 75  | 13,333       | 0,635    | 0,049    | 0        | sí                                     |
| 80  | 12,500       | 0,688    | 0,069    | 0        | sí                                     |
| 85  | 11,765       | 0,324    | 0,049    | 0        | **sí (la mayor)**                      |
| 90  | 11,111       | 0,028    | 0,047    | 0        | no: cumple, pero sin el margen         |
| 95  | 10,526       | −0,306   | 0,049    | −0,494   | no                                     |
| 100 | 10,000       | −1,145   | 0,039    | −8,953   | no                                     |

**Frecuencia óptima: 85 MHz.** No se probaron frecuencias mayores a 100 MHz porque ya falla a 95.

El WNS no baja de forma pareja con la frecuencia (80 MHz da más margen que 75), porque cada corrida ubica y rutea distinto. Por eso se barre en vez de calcular, y por eso se exige un margen.

### 4.2 Aplicación: Clock Wizard

Como la óptima es menor que 100 MHz, según la tabla de ADR-016 se usa un **MMCM**:

| Punto de ADR-016                 | Cómo quedó                                                                             |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| Frecuencia                       | 100 MHz × 40,375 / 4 / 11,875 = **85,000 MHz** exactos (VCO a 1009,375 MHz)            |
| Salida por BUFG                  | Sí (`u_clk/inst/clkout1_buf`), única red de reloj del sistema                          |
| `locked` como condición de reset | `r_rst_meta <= i_reset \|\| !w_locked`, más un segundo FF de sincronización (`top.v`)  |
| `COUNT_MAX` recalculado          | 85 MHz / (16 × 19200) = 276,7 → 277; baud real de 19 179 bps, **error 0,11 %** (< 2 %) |
| Versionado                       | Solo `TP3/hw/ip/clk_wiz_0/clk_wiz_0.xci`; `impl_top.tcl` regenera el resto (ADR-020)   |
| Restricción                      | El reloj de 85 MHz lo deriva Vivado del de 100 MHz del `.xdc`                          |

### 4.3 Antes y después

| Medida                        | 100 MHz directo | 85 MHz con MMCM                |
| ----------------------------- | --------------- | ------------------------------ |
| WNS                           | −1,316 ns       | +0,345 ns                      |
| TNS                           | −18,849 ns      | 0                              |
| WHS                           | +0,039 ns       | +0,054 ns                      |
| Skew del peor camino de setup | −0,034 ns       | −0,111 ns                      |
| Skew del peor camino de hold  | +0,266 ns       | +0,264 ns                      |
| Incertidumbre del reloj       | 0,035 ns        | 0,113 ns (jitter del MMCM)     |
| Potencia total estimada       | 0,094 W         | 0,210 W (el MMCM suma 0,122 W) |

El MMCM no es gratis: agrega jitter, que le quita unos 0,08 ns de margen a cada camino, y consume más que toda la lógica del diseño. A cambio, el sistema cumple con margen.

## 5. Qué se podría mejorar

Queda como trabajo futuro, no implementado:

| Idea                                                                                                 | Efecto esperado                                                                                                                                                      |
| ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Registrar la lectura de la DMEM en `du_dumper` (un ciclo entre la dirección y la selección del byte) | Elimina la familia Debug Unit → UART. Cuesta un ciclo por byte, irrelevante a 19 200 bps                                                                             |
| Con eso, el límite pasa al núcleo (forwarding → `branch_cmp` → PC)                                   | Ese camino también falla a 100 MHz (−0,443 ns), así que se llegaría a unos 90–95 MHz. Para 100 MHz habría que mover la resolución del branch o registrar la decisión |
| Memorias en BRAM (roadmap #5)                                                                        | Saca las LUTRAM del camino y libera 688 LUT, pero obliga a realinear IF y MEM con la lectura sincrónica                                                              |
