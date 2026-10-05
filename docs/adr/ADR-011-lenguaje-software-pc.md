# ADR-011 — Lenguaje del software de PC

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** Hito 1 (US-105)
- **Relacionados:** ADR-012 (interfaz), ADR-013 (ensamblador), ADR-014 (golden model)

## Contexto

Del lado de la PC hay que construir varias herramientas que comparten la misma tabla de instrucciones (PRD §4.2):

- tabla ISA, ensamblador y desensamblador;
- golden model (ADR-014);
- codec del protocolo y transporte serie (ADR-003);
- sesión de depuración, CLI e interfaz de usuario (ADR-012).

Requisitos que condicionan la elección:

- Funcionar en Linux (Mint/Ubuntu) y Windows 10+, y detectar el puerto serie de la Basys 3 (NFR-7).
- Cobertura de tests ≥ 80 % en general y ≥ 95 % en `isa/`, `assembler/` y `protocol/codec.py` (NFR-10).
- El volumen de datos es mínimo (cientos de bytes por snapshot a 19200 bps): el rendimiento no es un factor.
- El plazo es corto y el hardware ya consume la mayor parte del esfuerzo: conviene el lenguaje con el que el equipo es más productivo.

## Decisión

- **Python 3.11 o superior.**
- Proyecto en `tools/` gestionado con `pyproject.toml` (instalable con `pip install -e tools/`).
- Herramientas:
  - `pyserial` para el puerto serie (solo se importa en `protocol/serial_transport.py`, PRD §4.3);
  - `pytest` + `pytest-cov` para tests y cobertura;
  - `ruff` para lint y formato.
- La tabla ISA (`isa/`) usa solo la biblioteca estándar (US-105, AC4).
- **Idioma de los identificadores:** se respeta la convención que ya usa el PRD. Los nombres de dominio van en español (`instrucciones.py`, `ensamblar()`, `Imagen`, `LineaAsm`, `mnemonico`), y los términos técnicos sin traducción natural o que vienen de patrones conocidos van en inglés (`Transport`, `Snapshot`, `FakeTransport`, `encode_r`, `decode_*`). Comentarios y docstrings, en español.

## Alternativas consideradas

| Opción                      | Ventajas                                                                                                 | Desventajas                                                                      |
| --------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| **(a) Python 3.11+** (elegida) | Más experiencia del equipo; `pyserial` maduro y multiplataforma; muchas opciones de TUI/GUI; `dataclasses` y `match` para el decodificador | Más lento (irrelevante acá); distribuir un ejecutable requiere PyInstaller o similar |
| (b) C/C++                   | Rápido; binario nativo                                                                                   | Mucho más código para lo mismo; GUI costosa; manejo de puerto serie distinto por SO |
| (c) Go                      | Buen soporte serie; binarios portables sin dependencias                                                  | Menos opciones de GUI; el equipo tiene menos experiencia                         |

**Idioma de los identificadores**

| Opción                                   | Ventajas                                                        | Desventajas                                                                 |
| ---------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **(a) Mezcla como en el PRD** (elegida)  | El código coincide con los nombres del PRD y las historias de usuario; no hay que traducir nada | Sin una regla, cada uno puede elegir distinto: se fija el criterio de arriba |
| (b) Todo en inglés                       | Consistente con el Verilog y con las librerías                   | Los nombres no coinciden con el PRD                                         |
| (c) Todo en español                      | Consistente con la documentación                                 | Nombres forzados para conceptos sin traducción (`Transporte`, `Instantánea`) |

## Consecuencias

**Positivas**

- Una sola tecnología para todo el software de PC: ensamblador, golden model, protocolo e interfaz comparten la tabla ISA sin capas de interoperabilidad.
- Se puede probar todo sin placa con `FakeTransport` (NFR-9) y medir cobertura con `pytest-cov` (NFR-10).
- Los nombres del código coinciden con los del PRD, así que las historias de usuario se pueden seguir literalmente.

**Negativas**

- Cada integrante tiene que tener un entorno Python 3.11+ con las dependencias (se documenta en el `README.md` y se usa un `.venv`).
- La convención mixta de idioma requiere atención en las revisiones de código para que no se mezclen criterios dentro de un mismo módulo.

**Restricciones que impone**

- La versión mínima de Python se declara en `pyproject.toml` (`requires-python = ">=3.11"`) y en el `README.md`.
- `make test-py` corre `pytest` con cobertura; `ruff check` forma parte del DoD.
- Ningún módulo fuera de `ui/` importa el framework de interfaz, y ninguno fuera de `serial_transport.py` importa `pyserial`.

## Referencias

- PRD §4.2 a §4.5, §7 (NFR-7, NFR-9, NFR-10), §8 (ADR-011), §13 (idioma).
