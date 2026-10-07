# ADR-012 — Tecnología de la interfaz de usuario

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** Hito 5
- **Relacionados:** ADR-011 (Python), ADR-014 (golden model y `FakeTransport`)

## Contexto

El enunciado pide ser creativos con la interfaz (GUI, TUI o CLI). No tiene que ser muy elaborada, pero sí prolija. La interfaz tiene que mostrar, para cada paso:

- el pipeline: qué instrucción hay en cada etapa y si es una burbuja (`valid = 0`);
- dónde actuaron forwarding, stall y flush en ese ciclo;
- los 32 registros y la memoria usada, resaltando lo que cambió respecto del paso anterior;
- el programa fuente con la línea que se está ejecutando;
- controles para `LOAD`, `STEP`, `RUN`, `ABORT`, `RESET` y `DUMP`.

Restricciones: Python (ADR-011), Linux y Windows (NFR-7), uso sin placa con `--fake` (NFR-9), y un plazo en el que el hardware se lleva la mayor parte del esfuerzo.

## Decisión

- **La GUI se hace con Flet** (Python puro, renderizado con Flutter), como aplicación de escritorio.
- Vistas previstas en `ui/views/`:
  - `pipeline_view.py`: 5 columnas (IF, ID, EX, MEM, WB) con la instrucción desensamblada, colores para burbuja, stall, flush y forwarding, y flechas o indicadores de forwarding. Se arma con contenedores de Flet o `flet.canvas`.
  - `registers_view.py`: tabla de 32 registros con formato `x5 (t0)` y valores en hex, resaltando los que cambiaron.
  - `memory_view.py`: palabras usadas de la DMEM (ADR-008), con `DUMP_MEM` para ver otros rangos.
  - `editor_view.py`: editor de texto del programa y listado ensamblado con la línea en ejecución resaltada (usando `Imagen.mapa_lineas`).
- **Se mantiene una CLI** (`cli/main.py`, US-411) para pruebas automatizadas y uso desde scripts.
- Las operaciones de puerto serie, que son bloqueantes, corren fuera del hilo de la interfaz (async o un hilo de trabajo en `session/`), para que la GUI no se congele durante un `RUN` largo.
- La versión de Flet se fija en `pyproject.toml`.

## Alternativas consideradas

| Opción                               | Ventajas                                                                                               | Desventajas                                                                                         |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| (a) Textual (TUI)                    | Muy vistosa para el esfuerzo; tablas, colores y atajos de teclado; corre en cualquier terminal          | No tiene un editor de código rico; poca libertad para dibujar el diagrama del pipeline              |
| **(b) Flet** (elegida)               | Ya se usó en StatsPro, así que el equipo lo conoce y se arma rápido; GUI real con colores y layout libre; Python puro | Menos control fino del layout que Qt; depende del runtime de Flutter; la API cambia bastante entre versiones |
| (c) PySide6 / Qt                     | Muy completo; editor con resaltado de sintaxis; dibujo libre del datapath                              | Curva de aprendizaje mayor y mucho más código                                                       |
| (d) Web local (FastAPI + navegador)  | Máxima libertad visual (SVG del pipeline)                                                               | Dos procesos, websockets y más piezas que mantener                                                  |

Se elige Flet porque el equipo ya lo usó y en el plazo disponible la experiencia previa pesa más que la potencia de Qt: permite una GUI gráfica (mejor para mostrar el pipeline que una TUI) sin la curva de aprendizaje de PySide6.

## Consecuencias

**Positivas**

- Interfaz gráfica de escritorio, adecuada para la defensa, desarrollada con una herramienta conocida.
- Corre en Linux y Windows sin cambios.
- Gracias a la regla de dependencias (PRD §4.3), solo `ui/` conoce Flet: si hubiera que cambiar de framework, se reescribe únicamente esa capa.
- Con `FakeTransport` se puede desarrollar toda la GUI antes de que el hardware esté listo.

**Negativas**

- Flet no trae un editor de código con resaltado de sintaxis: el editor es un campo de texto multilínea, y el resaltado se limita al listado ensamblado (por ejemplo, con un bloque de código en `Markdown`).
- Dibujar el datapath con flechas de forwarding requiere `flet.canvas` o trucos de layout; es más trabajo que en Qt o SVG.
- La API de Flet cambia entre versiones menores: hay que fijar la versión y no actualizarla durante el proyecto.
- Agrega una dependencia pesada (el runtime de Flutter) a la instalación.

**Restricciones que impone**

- Ninguna vista accede al puerto serie ni a bytes crudos: reciben objetos `Snapshot` de `session/` (PRD §4.6).
- La comunicación con la placa no bloquea el hilo de la interfaz.
- `ui/app.py` es el único lugar que decide qué transporte se usa (`--port` o `--fake`).

## Referencias

- PRD §4.2 a §4.6, §7 (NFR-4, NFR-7, NFR-9), §8 (ADR-012); Hito 5 (US-503 a US-507).
