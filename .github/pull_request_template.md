<!--
Título del PR: tipo(alcance): descripción  →  ej. feat(core): forwarding desde EX/MEM
Tipos: feat · fix · test · docs · refactor · sim · synth
Rama: feature/us-XXX-descripcion → develop   (hotfix/descripcion → main + develop)
-->

## Historia / issue relacionada

Closes #
**US:** US-XXX — <!-- título de la historia -->
**Épica / Hito:** HX-EY · Hito X (vX.Y)

## Tipo de cambio

- [ ] `feat` — funcionalidad nueva
- [ ] `fix` — corrección de un defecto (severidad: <!-- Crítico / Alto / Medio / Bajo -->)
- [ ] `test` / `sim` — testbenches, programas de prueba o verificación
- [ ] `synth` — síntesis, restricciones, timing, Clock Wizard
- [ ] `refactor` — sin cambio de comportamiento
- [ ] `docs` — documentación, ADR, informe

## Área afectada

- [ ] Hardware — núcleo (`hw/rtl/core/`)
- [ ] Hardware — Debug Unit / UART (`hw/rtl/debug/`, `hw/rtl/uart/`)
- [ ] Assembly (`asm/`)
- [ ] Software de PC (`tools/`)
- [ ] Documentación (`docs/`)
- [ ] Toca un **módulo crítico** (ver `docs/catalogo-criticidad.md`)

## Qué cambia y por qué

<!-- Resumen corto. Si se tomó una decisión de diseño, mencionar el ADR. -->

## Cómo se probó

<!-- Comandos ejecutados y resultado. Borrar lo que no aplique. -->

- `make sim-all`:
- `make verify`:
- `pytest` / `ruff`:
- Prueba en placa (Basys 3):
- Modo `--fake`:

## Síntesis y timing (si toca RTL)

| Métrica                   | Antes | Después |
| ------------------------- | ----- | ------- |
| WNS (ns)                  |       |         |
| WHS (ns)                  |       |         |
| LUTs (%)                  |       |         |
| BRAM (%)                  |       |         |
| Frecuencia vigente (MHz)  |       |         |

## Checklist — Definición de "Hecho" (sección 11 del PRD)

Marcar lo que aplique; tachar (`~~texto~~`) lo que no corresponda a este PR.

- [ ] Commits con formato `tipo(alcance): descripción`
- [ ] **Testbench:** cada módulo nuevo/modificado tiene testbench autoverificable y `make sim-all` pasa completo
- [ ] **Regresión:** si toca núcleo o Debug Unit, `make verify` pasa al 100 %
- [ ] **Síntesis limpia:** sin _critical warnings_, sin latches inferidos, sin _multi-driven nets_; cumple timing a la frecuencia vigente
- [ ] **Reloj intacto:** ninguna expresión usa `clock` fuera de `@(posedge clock)`
- [ ] **Software:** `pytest` pasa, `ruff` sin errores, cobertura según NFR-10
- [ ] **Contratos:** si cambió interfaz del núcleo, protocolo o un latch → actualizados `docs/interfaces/`, `docs/protocolo.md`, `du_dumper.v` y `protocol/snapshot.py` **en este PR**
- [ ] **ADR:** la decisión requerida está aprobada y en `docs/adr/`
- [ ] **Estilo:** respeta sección 6.2 (Verilog: `i_`/`o_`/`r_`/`w_`, reset sincrónico, sin números mágicos) y sección 15
- [ ] **Documentación:** encabezado en cada módulo Verilog y docstring en cada función pública de Python
- [ ] **UI:** probada con placa y en modo `--fake`
- [ ] **CHANGELOG:** entrada en `[Unreleased]` con prefijo `[hw]` / `[sw]`
- [ ] No se suben archivos generados por Vivado (`*.runs/`, `*.cache/`, `*.sim/`, `.Xil/`, `.bit`)

## Notas para el revisor

<!-- Qué mirar con más atención, riesgos, capturas de ondas o de la GUI, reportes adjuntos. -->
