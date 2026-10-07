# ADR-014 — Simulador de referencia (golden model)

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-107, US-305, US-506
- **Relacionados:** ADR-008 (memoria usada), ADR-009 (estado inicial en cero), ADR-011 (Python), ADR-012 (GUI), ADR-013 (tabla ISA compartida), ADR-018 (desalineados e ilegales)

## Contexto

Para afirmar que un resultado de la placa (o de la simulación RTL) es correcto, hace falta un **resultado esperado**. Sin una referencia automática hay que calcularlo a mano para cada programa, lo que no escala a la suite de pruebas (32 instrucciones + HALT, casos de riesgo y demos) ni a la métrica principal del proyecto: el 100 % de los programas con un estado final que coincida con el esperado (PRD §1.4).

Además, la pista de software necesita desarrollar la GUI antes de que el hardware esté listo (NFR-9), y para eso hace falta algo que responda como la placa.

## Decisión

Se combinan dos mecanismos complementarios:

### (a) ISS propio en Python (`iss/golden_model.py`)

- Ejecuta **una instrucción por paso**, sin modelar el pipeline: es la semántica de la ISA, no la del hardware.
- Usa la tabla ISA compartida (`isa/`), la misma que el ensamblador (ADR-013). No depende del ensamblador: recibe palabras, no texto.
- Estado: `pc`, `regs[32]`, `dmem`, `mem_escrita` (misma definición de "usada" que ADR-008), `instrucciones_retiradas`. Arranca todo en cero, igual que el hardware después de `LOAD` (ADR-009).
- `run(max_instr)` se detiene en HALT o al llegar al límite (informa `TIMEOUT` y no se cuelga).
- Comportamiento de desalineados e ilegales según ADR-018.
- Usos:
  - **Verificación cruzada automática** RTL / placa vs. golden model (US-305): se comparan registros y memoria usada al final.
  - **`FakeTransport`** (US-410): responde al protocolo usando el ISS, así la GUI y la CLI funcionan sin placa. Los latches se aproximan sin riesgos y el snapshot se marca `simulado = True`.
  - **Modo "verificar" en la GUI** (US-506): compara el estado de la placa con el esperado.

### (b) Firma en memoria en cada programa de prueba

- Cada programa de `asm/tests/` escribe al final una **firma de éxito o de falla** en una dirección fija de la DMEM, calculada por el propio programa (por ejemplo, comparando un resultado con el valor esperado y saltando a la rama de falla si no coincide).
- La dirección y los valores de la firma se fijan en `asm/README.md` (propuesta: última palabra de la DMEM, `0x3FC`; éxito = `0x00000001`, falla = número de caso que falló).
- Permite verificar un programa leyendo una sola palabra, aunque no se tenga el ISS a mano (por ejemplo, en un testbench Verilog o en la defensa).

## Alternativas consideradas

| Opción                                        | Ventajas                                                                                       | Desventajas                                                                                                 |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **(a) + (b): ISS propio + firma** (elegida)   | Comparación automática completa (todo el estado) y verificación rápida por programa; habilita `FakeTransport` | Dos mecanismos que mantener; ~3 días·persona para el ISS                                                    |
| Solo ISS propio                               | Un único mecanismo, compara todo el estado                                                     | Para verificar en un testbench Verilog o en la placa hace falta correr el ISS y comparar                    |
| Solo firma en memoria                         | Sin código extra en Python                                                                     | Solo verifica lo que el programa chequea; sin ISS no hay `FakeTransport` ni modo verificar; incumple NFR-9   |
| RARS / Spike como referencia manual           | Simuladores maduros                                                                            | Comparación manual; no conocen HALT (`custom-0`); no se integran con la GUI                                 |

## Consecuencias

**Positivas**

- La métrica principal (100 % de la suite correcta en placa) se mide automáticamente.
- Toda la GUI se puede desarrollar y probar sin placa (NFR-9).
- Si el ISS y el hardware difieren, la firma ayuda a decidir quién tiene el error: el programa sabe cuál es su resultado correcto.
- Se detectan errores de interpretación de la ISA en dos implementaciones independientes (Python y Verilog).

**Negativas**

- El ISS es una segunda implementación de la ISA: si ambos (ISS y RTL) interpretan mal una instrucción de la misma forma, la comparación no lo detecta. Se mitiga con los tests de valores borde del ISS (US-107, AC1) y con la firma, que se calcula con valores esperados escritos a mano.
- Los latches que muestra `FakeTransport` son una aproximación: no sirven para verificar riesgos.
- La firma usa una palabra de la DMEM y siempre aparece en la memoria usada.

**Restricciones que impone**

- El ISS y el hardware tienen que coincidir en el estado inicial (ADR-009), en la definición de memoria usada (ADR-008) y en el tratamiento de desalineados e ilegales (ADR-018).
- Ningún programa de prueba puede usar la dirección de la firma para otra cosa.
- `EstadoArquitectonico` del ISS usa el mismo formato que la parte de registros y memoria del `Snapshot`, para poder compararlos directamente.

## Referencias

- PRD §1.4 (métricas), §4.4 (`FakeTransport`), §7 (NFR-9), §8 (ADR-014); US-107, US-305, US-410, US-506.
