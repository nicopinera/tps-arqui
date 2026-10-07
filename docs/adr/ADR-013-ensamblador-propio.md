# ADR-013 — Ensamblador propio vs. toolchain externo

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-106, US-108
- **Relacionados:** ADR-004 (HALT), ADR-008 (tamaño de IMEM), ADR-010 (HALT automático), ADR-011 (Python), ADR-014 (golden model)

## Contexto

El enunciado exige "contar con un mecanismo para traducir instrucciones a lenguaje máquina" y pide originalidad ("no copien, sean únicos"). El ensamblador tiene que:

- codificar las 32 instrucciones del enunciado más HALT, que no existe en RV32I (ADR-004);
- resolver etiquetas como offsets relativos al PC en branches y `jal`, con los inmediatos partidos y reordenados de los formatos B y J (PRD §2.2);
- producir `.hex` para simulación (`$readmemh`), `.bin` para la UART y un listado para la GUI;
- rechazar programas que no entren en la IMEM (R-PR-2) y agregar HALT si falta (R-PR-1, ADR-010).

## Decisión

### Ensamblador propio de dos pasadas, en Python

- **Primera pasada:** asigna direcciones (PC += 4 por instrucción, ya con las pseudoinstrucciones expandidas) y arma la tabla de símbolos.
- **Segunda pasada:** resuelve las etiquetas y codifica usando `isa/formatos.py`, la misma tabla que usan el desensamblador y el golden model.
- El toolchain GNU (`riscv64-unknown-elf-as -march=rv32i`) se usa **solo para validar**: se genera una vez un `.hex` de referencia con las 32 instrucciones estándar, se versiona en `tools/tests/fixtures/` y el test compara contra ese archivo (US-106, AC2). Los tests no necesitan GNU instalado.

### Alcance del lenguaje

- Etiquetas (`loop:`), comentarios con `#`.
- Registros por número (`x5`) y por nombre ABI (`t0`).
- Inmediatos decimales, hexadecimales (`0x…`) y negativos.
- Sintaxis `offset(rs1)` para loads, stores y `jalr`.
- Directiva `.word` para insertar palabras crudas.
- **No hay sección `.data`:** los datos iniciales de la DMEM se escriben con `sw`/`sh`/`sb` desde el programa (lo que además ejercita los stores). `.data` queda en el roadmap (PRD §14, A12).
- `halt` como mnemónico nativo; si el programa no termina en HALT, se agrega uno con una advertencia.

### Pseudoinstrucciones soportadas

Todas se expanden a **exactamente una** instrucción, así que la primera pasada sigue siendo "4 bytes por línea":

| Pseudo        | Expansión               |
| ------------- | ----------------------- |
| `nop`         | `addi x0, x0, 0`        |
| `mv rd, rs`   | `addi rd, rs, 0`        |
| `j etiqueta`  | `jal x0, etiqueta`      |
| `ret`         | `jalr x0, 0(x1)`        |

`li` no se soporta: para cargar constantes se usan `addi` (12 bits) o `lui` + `addi` de forma explícita.

## Alternativas consideradas

| Opción                                     | Ventajas                                                                                                    | Desventajas                                                                                                       |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **(a) Ensamblador propio de dos pasadas** (elegida) | Son solo 33 instrucciones; reutiliza la tabla ISA; HALT nativo; mensajes de error propios; genera el mapa dirección → línea para la GUI; responde al "sean únicos" | ~6 días·persona de desarrollo (US-106 y US-108)                                                                            |
| (b) `riscv64-unknown-elf-as` + `objcopy`   | No hay que escribir el ensamblador; codificación garantizada                                                | HALT solo como `.word 0x0000000B`; hay que instalar el toolchain en ambas máquinas y en Windows; no da el mapa de líneas |
| (c) Exportar desde RARS / Venus            | Simuladores educativos conocidos                                                                            | Paso manual en otra herramienta; difícil de automatizar; HALT tampoco existe                                      |

**Pseudoinstrucciones**

| Opción                                | Ventajas                                         | Desventajas                                                                                       |
| ------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| **`nop`, `mv`, `j`, `ret`** (elegida) | Expansión 1 a 1; programas más legibles          | —                                                                                                 |
| + `li`                                | Cómodo para cargar constantes                    | Se expande a 1 o 2 instrucciones según el valor: la primera pasada tiene que calcular tamaños variables |
| + `beqz`, `bnez`                      | Comparaciones contra cero más legibles           | Poco valor agregado; se pueden escribir como `beq rs, x0, …`                                      |
| Ninguna                               | Mínimo trabajo                                   | Programas de prueba menos legibles                                                                |

## Consecuencias

**Positivas**

- Una sola fuente de verdad para la codificación: un error se corrige en `isa/` y se arregla en ensamblador, desensamblador y golden model a la vez.
- La validación contra GNU da confianza en la codificación de las 32 instrucciones estándar sin depender de GNU en el uso diario.
- Mensajes de error con número de línea pensados para este proyecto (US-106, AC4).
- El listado `.lst` y `mapa_lineas` permiten que la GUI resalte la línea en ejecución.

**Negativas**

- Es código propio que hay que mantener y probar (cobertura ≥ 95 %, NFR-10).
- Sin `li` ni `.data`, los programas que necesitan constantes grandes o datos iniciales son más largos.

**Restricciones que impone**

- El ensamblador rechaza programas de más de 256 palabras (ADR-008), contando el HALT agregado.
- Los inmediatos de `slli`/`srli`/`srai` se limitan a 0–31; los de B y J tienen que ser pares y estar en rango (US-105, AC3).
- El listado `.lst` muestra la expansión de cada pseudoinstrucción (US-108, AC4).

## Referencias

- PRD §2.2 (codificación), §6 (R-PR-1, R-PR-2), §8 (ADR-013), §14 (A12, A13); US-105, US-106, US-108.
