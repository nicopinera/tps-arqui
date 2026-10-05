# ADR-020 — Versión de Vivado de referencia

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-101
- **Relacionados:** ADR-005 (sin IP de memoria), ADR-015 (xsim), ADR-016 (Clock Wizard)

## Contexto

El informe del TP2 se hizo con **Vivado 2025.2**, y al menos una máquina del equipo tiene **2026.1**. Entre versiones de Vivado:

- los proyectos (`.xpr`) se "actualizan" al abrirlos en una versión más nueva y después no abren en la anterior;
- los IP (`.xci`: Clock Wizard, Block Memory Generator) quedan bloqueados (_locked_) si se abren en una versión distinta a la que los generó, y hay que actualizarlos;
- los resultados de síntesis e implementación (recursos, WNS/WHS) pueden variar, lo que afecta a los números del informe.

NFR-8 exige que el proyecto se regenere desde el repositorio con un solo script, sin pasos manuales.

## Decisión

- **La versión de referencia es Vivado 2025.2**, la misma del TP2.
- Se declara en:
  - el `README.md` (sección de requisitos);
  - `hw/scripts/create_project.tcl`, que verifica la versión al arrancar (`version -short`) y aborta con un mensaje claro si no coincide.
- **No se versiona el proyecto de Vivado**: se regenera con `make project` desde los scripts TCL (US-101).
- **Si se usa IP** (Clock Wizard en ADR-016): se versiona el `.xci` en `hw/ip/` y se regenera desde el script. No se versionan los productos generados del IP.
- Todos los números del informe (recursos, timing, potencia) se obtienen con 2025.2.

## Alternativas consideradas

| Opción                                | Ventajas                                                                                         | Desventajas                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| **(a) 2025.2** (elegida)              | Es la versión con la que el TP2 ya funciona en placa; los módulos de UART migran sin riesgo; los números son comparables con el informe del TP2 | Quien tenga solo 2026.1 tiene que instalar 2025.2 (instalación de varios GB)                 |
| (b) 2026.1                            | Versión más nueva                                                                                | Hay que volver a validar la migración del TP2; el otro integrante tiene que actualizar        |
| (c) Sin versión fija                  | Nadie instala nada                                                                               | IP bloqueados, proyectos que no abren y números de timing que cambian según quién sintetiza  |

## Consecuencias

**Positivas**

- La migración del TP2 (US-101, AC3) se hace en la misma versión con la que se verificó.
- Los resultados de síntesis e implementación son reproducibles entre las dos máquinas.
- La comparación de recursos y frecuencia con el TP2 (US-603) es directa.

**Negativas**

- Puede ser necesario tener dos versiones de Vivado instaladas en una de las máquinas.
- No se aprovechan mejoras de 2026.1 (no hay ninguna conocida que el proyecto necesite).

**Restricciones que impone**

- `create_project.tcl` aborta si la versión no es 2025.2.
- Un cambio de versión durante el proyecto requiere un nuevo ADR que reemplace a este, y repetir las mediciones de timing antes de usarlas en el informe.
- El CI (ADR-015) no usa Vivado: corre Python e Icarus, así que no depende de esta versión.

## Referencias

- PRD §7 (NFR-8), §8 (ADR-020); US-101.
- Informe del TP2 (versión de Vivado utilizada).
