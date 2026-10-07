# Changelog

Todos los cambios relevantes del TP3 se registran en este archivo.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen el esquema de la sección 15 del PRD.

## [Unreleased]

### Added

- Estructura de carpetas de `TP3/` (`hw/rtl`, `hw/constraints`) y `Makefile` con los objetivos de simulación pendientes de US-102 (US-101).
- Módulos UART del TP2 migrados sin cambios a `hw/rtl/uart/` (US-101).
- `hw/rtl/legacy/` con `alu_tp1.v`, `uart_interface.v` y `top_tp2.v` como referencia y prueba de humo de la migración (US-101).
- `hw/constraints/basys3.xdc` basado en las constraints del TP2 (US-101).
- `docs/catalogo-criticidad.md` inicializado desde la sección 11 del PRD (US-101).
