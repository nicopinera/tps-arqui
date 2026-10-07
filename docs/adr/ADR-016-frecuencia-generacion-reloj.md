# ADR-016 — Frecuencia de operación y generación de reloj

- **Estado:** Propuesto (se aprueba con los datos de US-601 / US-602)
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** Hito 6
- **Relacionados:** ADR-001 (clock enable, fan-out de `i_enable`), ADR-002 (`COUNT_MAX` parametrizado), ADR-005 (memoria distribuida en el camino crítico), ADR-007 (forwarding en EX)

## Contexto

El enunciado pide encontrar la frecuencia de funcionamiento óptima y "aplicarla en el sistema" si hay skew o problemas de timing, e invita a investigar el Clock Wizard. Hay dos aclaraciones del PRD que enmarcan esta decisión:

- **E4/E5 (PRD §14):** el camino crítico no genera skew; el skew es la diferencia de llegada del reloj y siempre existe en algún grado. La condición que importa es si el diseño **cumple timing** (WNS ≥ 0 y WHS ≥ 0) a la frecuencia elegida.
- **C2 (PRD §14):** generar otra frecuencia con el MMCM por la red dedicada de reloj **no** es intervenir el clock. Lo prohibido es meter lógica en el camino del reloj (compuertas o divisores con flip-flops).

Datos que todavía no existen y que deciden este ADR:

- WNS/WHS post-implementación del sistema integrado a 100 MHz (US-601).
- Cuál es el camino crítico. Candidatos esperables: forwarding → ALU → comparación de branch → mux del PC (ADR-006/007); lectura combinacional de IMEM/DMEM → extensión de loads → forwarding (ADR-005); fan-out de `i_enable` (ADR-001).
- Barrido de frecuencias con su WNS/WHS (US-602).

Referencia previa: el diseño del TP2 cerraba a 100 MHz con WNS = 4,899 ns, pero era mucho más chico.

## Decisión propuesta (criterio)

1. **Medir a 100 MHz** con el reloj de la placa directo (US-601): `report_timing_summary`, los 10 peores caminos de setup y hold, `report_clock_networks` y el skew de los caminos críticos.
2. **Barrer frecuencias** con un script TCL (`freq_sweep.tcl`), por ejemplo 50, 75, 100, 110, 125, 140 y 150 MHz, y registrar WNS/WHS de cada una.
3. **Frecuencia óptima** = la mayor frecuencia del barrido con **WNS ≥ 0,3 ns y WHS ≥ 0** (el margen deja lugar para variaciones de implementación entre corridas).
4. **Aplicación:**

   | Resultado del análisis                                         | Acción                                                                                                                                         |
   | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
   | La óptima es 100 MHz                                           | Se documenta y se usa el reloj de la placa directo (sin MMCM). En el informe se explica por qué no hace falta el Clock Wizard                    |
   | La óptima es **menor** que 100 MHz (no cierra a 100)           | Clock Wizard (MMCM) que genera la frecuencia óptima                                                                                             |
   | La óptima es **mayor** que 100 MHz y la ganancia es significativa | Clock Wizard que genera la frecuencia óptima; se evalúa si la ganancia justifica la complejidad (se decide al aprobar este ADR)                  |

5. **Si se usa el MMCM:**
   - salida por BUFG (lo hace el Clock Wizard);
   - la señal `locked` mantiene el reset del sistema activo hasta que el reloj esté estable;
   - se recalcula `COUNT_MAX` con la nueva `CLK_FREQ_HZ` (ADR-002) y se verifica que el error de baud sea < 2 %;
   - se versiona solo el `.xci` en `TP3/hw/ip/` (ADR-020).
6. **En todos los casos** se documentan WNS, WHS y skew antes y después en `docs/informe/timing.md`, y se repite la suite completa en placa a la frecuencia final.

## Alternativas consideradas

| Opción                                          | Ventajas                                                                                     | Desventajas                                                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| (a) 100 MHz directo, MMCM solo si no cierra     | Lo más simple; sin IP si no hace falta                                                       | Si cierra con mucho margen, no se aprovecha; la consigna de "aplicar la frecuencia óptima" queda solo argumentada  |
| (b) MMCM siempre, aunque genere 100 MHz         | Cambiar la frecuencia es tocar un parámetro del IP; responde de forma práctica a la consigna | Agrega un IP y la lógica de `locked` aunque no haga falta                                                         |
| **(c) Decidir con datos según el criterio de arriba** (propuesta) | La decisión queda respaldada por los reportes; el criterio se fija antes de ver los números | Este ADR queda abierto hasta el Hito 6                                                                            |
| (d) Divisor de reloj con flip-flops             | Sin IP                                                                                       | **Prohibido**: es intervenir el clock; saca el reloj de la red dedicada (ADR-001)                                 |

## Consecuencias

**Positivas**

- El criterio (margen mínimo y barrido) se fija antes de tener los números, así la elección no es arbitraria.
- Las respuestas a las preguntas del enunciado sobre camino crítico, skew y frecuencia óptima quedan respaldadas por reportes versionados en `hw/reports/`.
- Gracias a ADR-002, la UART se adapta a cualquier frecuencia cambiando un parámetro.

**Negativas**

- El ADR queda abierto hasta el Hito 6: si el timing no cierra a 100 MHz, el ajuste llega tarde en el cronograma.
- Si se usa el MMCM, se agrega un IP con dependencia de la versión de Vivado (ADR-020) y el `top` no se puede simular en Icarus (ADR-015).

**Restricciones que impone**

- Desde el Hito 2, cada build guarda WNS/WHS para detectar temprano si el timing se degrada.
- El RTL no puede asumir 100 MHz en ningún lado: toda constante que dependa del tiempo se calcula desde `CLK_FREQ_HZ`.
- El reloj del núcleo, la Debug Unit y la UART es el mismo (un único dominio de reloj, ADR-001), sea el de la placa o el del MMCM.

## Pendiente para aprobar

- [ ] Resultados de US-601 (camino crítico y skew a 100 MHz).
- [ ] Tabla del barrido de US-602.
- [ ] Frecuencia elegida y si se usa el MMCM.
- [ ] Suite completa en placa a la frecuencia final.

## Referencias

- PRD §1.1 (problema 8), §7 (NFR-1, NFR-2), §8 (ADR-016), §14 (E4, E5, C2); US-601, US-602.
