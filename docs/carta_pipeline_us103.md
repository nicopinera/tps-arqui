# Carta de pipeline — US-103 AC4

> **Estado:** completa
> **Autor:** Julián Krede
> **Se reutiliza en:** US-507 AC2. La carta que dibuje la GUI tiene que coincidir con esta.

Recorrido "en papel", ciclo por ciclo, de un programa de **10 instrucciones** con un load-use, un forwarding EX/MEM y un `beq` tomado (PRD §9, US-103 AC4). Los nombres de señales son los de `docs/diagramas/datapath_pipeline.drawio`, página 2 "Datapath TP3".

---

## 1. Requisitos

- [x] El programa tiene 10 instrucciones.
- [x] **Load-use:** un `lw` seguido **inmediatamente** por una instrucción que lee su `rd` (1 stall).
- [x] **Forwarding EX/MEM:** un productor **de ALU** seguido inmediatamente por su consumidor (`fwd = 10`).
- [x] **`beq` tomado:** las 2 instrucciones que siguen en memoria se descartan (flush, 2 ciclos de penalidad).
- [x] Las instrucciones descartadas escriben registros que cambiarían el resultado si se ejecutaran, así el flush se puede comprobar.

## 2. Supuestos

- Registros y DMEM en 0 al arrancar (ADR-009).
- Predicción _not-taken_; `beq`/`bne`/`jalr` se resuelven en EX y `jal` en ID (ADR-006).
- Forwarding EX/MEM > MEM/WB, stall solo por load-use y bypass del banco WB→ID (ADR-007).
- Memorias con lectura combinacional (ADR-005).
- Ciclo 1 = primer ciclo con `i_enable = 1` después del reset: la instrucción #1 está en IF.
- El HALT en ID activa `halt_fetch`: el PC se congela y lo que se buscó detrás del HALT se descarta (burbuja en IF/ID). La IMEM después del programa está rellena con HALT (ADR-009).

## 3. Programa

| #   | Dirección | Instrucción       | Qué hace / para qué está            |
| --- | --------- | ----------------- | ----------------------------------- |
| 1   | `0x00`    | addi x5, x0, 0x1F | productor en forwarding             |
| 2   | `0x04`    | sw x5, 0(x0)      | consumidor en forwarding            |
| 3   | `0x08`    | lw x6, 0(x0)      | productor load-use                  |
| 4   | `0x0C`    | beq x5, x6, subru | beq tomado y consumidor en load-use |
| 5   | `0x10`    | addi x5, x5, -15  | se descarta por flush               |
| 6   | `0x14`    | sw x5, 8(x0)      | se descarta por flush               |
| 7   | `0x18`    | lw x6, 8(x0)      | se saltea, nunca se busca           |
| 8   | `0x1C`    | subru: nop        | direccion del salto y relleno       |
| 9   | `0x20`    | nop               | relleno                             |
| 10  | `0x24`    | halt              | Fin del programa                    |

**Offset del `beq`:** destino = `PC_beq + offset` = `0x0C + 0x10` = `0x1C` → instrucción

## 4. Dependencias (predicción antes de dibujar)

Una fila por cada registro leído que haya producido una instrucción anterior del programa. Las lecturas de `x0` no son dependencias (la Forwarding Unit exige `rd != 0`).

| Consumidor (#) | Registro   | Productor (#) | ¿ALU o load? | Distancia | Resultado esperado (`10` / `01` / stall / bypass / banco)                                                                                                                                       |
| -------------- | ---------- | ------------- | ------------ | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2              | x5 (`rs2`) | 1             | ALU          | 1         | **`fwd_b = 10`** (ciclo 4). Es el dato a guardar de la `sw`                                                                                                                                     |
| 4              | x6 (`rs2`) | 3             | load         | 1         | **1 stall** (ciclo 5) + **`fwd_b = 01`** (ciclo 7)                                                                                                                                              |
| 4              | x5 (`rs1`) | 1             | ALU          | 3         | La tabla dice bypass, pero **por el stall sale del banco**: en el ciclo 5 el bypass actúa, pero ese valor se pierde con la burbuja; en el ciclo 6 #4 relee x5 y #1 ya lo escribió. `fwd_a = 00` |
| 5              | x5 (`rs1`) | 1             | ALU          | 4         | Banco (lee en ID en el ciclo 7), pero se descarta: no llega a EX                                                                                                                                |
| 6              | x5 (`rs2`) | 5             | ALU          | 1         | Sería `fwd_b = 10`, pero #6 se descarta en IF: nunca llega a ID ni a EX                                                                                                                         |

## 5. Carta (instrucciones × ciclos)

Notación:

- `IF` `ID` `EX` `MEM` `WB`: etapa que ocupa la instrucción en ese ciclo.
- **Stall:** la etapa se repite (`ID` `ID`, `IF` `IF`) y en EX queda un hueco (burbuja).
- **Flush:** `✗` después de la última etapa alcanzada; la fila no avanza más.
- Una fila por instrucción **buscada**, incluidas las que se descartan y lo que se busque detrás del `halt`.
- Control: en cada columna, cada etapa la ocupa **a lo sumo una** instrucción.

| Instrucción                   | 1   | 2   | 3   | 4   | 5   | 6   | 7   | 8   | 9   | 10  | 11  | 12  | 13  | 14  |
| ----------------------------- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| #1 addi x5, x0, 0x1F          | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |
| #2 sw x5, 0(x0)               | -   | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |
| #3 lw x6, 0(x0)               | -   | -   | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |
| #4 beq x5, x6, subru          | -   | -   | -   | IF  | ID  | ID  | EX  | MEM | WB  |     |     |     |     |     |
| #5 addi x5, x5, -15           | -   | -   | -   | -   | IF  | IF  | ID  | ✗   |     |     |     |     |     |     |
| #6 sw x5, 8(x0)               | -   | -   | -   | -   | -   | -   | IF  | ✗   |     |     |     |     |     |     |
| #7 lw x6, 8(x0) (no se busca) |     |     |     |     |     |     |     |     |     |     |     |     |     |     |
| #8 subru: nop                 | -   | -   | -   | -   | -   | -   | -   | IF  | ID  | EX  | MEM | WB  |     |     |
| #9 nop                        | -   | -   | -   | -   | -   | -   | -   | -   | IF  | ID  | EX  | MEM | WB  |     |
| #10 halt                      | -   | -   | -   | -   | -   | -   | -   | -   | -   | IF  | ID  | EX  | MEM | WB  |
| `0x28` (HALT de relleno)      | -   | -   | -   | -   | -   | -   | -   | -   | -   | -   | IF  | ✗   |     |     |

Ocupación por etapa:

| Ciclo | IF     | ID  | EX  | MEM | WB  |
| ----- | ------ | --- | --- | --- | --- |
| 1     | #1     | —   | —   | —   | —   |
| 2     | #2     | #1  | —   | —   | —   |
| 3     | #3     | #2  | #1  | —   | —   |
| 4     | #4     | #3  | #2  | #1  | —   |
| 5     | #5     | #4  | #3  | #2  | #1  |
| 6     | #5     | #4  | —   | #3  | #2  |
| 7     | #6     | #5  | #4  | —   | #3  |
| 8     | #8     | —   | —   | #4  | —   |
| 9     | #9     | #8  | —   | —   | #4  |
| 10    | #10    | #9  | #8  | —   | —   |
| 11    | `0x28` | #10 | #9  | #8  | —   |
| 12    | —      | —   | #10 | #9  | #8  |
| 13    | —      | —   | —   | #10 | #9  |
| 14    | —      | —   | —   | —   | #10 |

## 6. Eventos por ciclo

Solo los ciclos en los que pasa algo. Nombrá la señal y el bloque de la página 2 del datapath.

| Ciclo | Evento                       | Señales (valor)                                                                                | Bloque del datapath                      |
| ----- | ---------------------------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------- |
| 4     | Forwarding EX/MEM            | `fwd_a = 00`, `fwd_b = 10` (#1 en MEM, `rdM = x5`)                                             | Forwarding Unit, muxes de EX             |
| 5     | Stall load-use               | `StallF = 1`, `StallD = 1`, `FlushE = 1` (#3 en EX con `mem_readE`, `rdE = x6` = `rs2D` de #4) | Hazard Unit                              |
| 5     | Bypass del banco (se pierde) | #1 en WB escribe x5 y #4 lo lee en ID; el valor no se latchea por el stall                     | Banco de registros (mux de bypass)       |
| 6     | Burbuja en EX                | `validE = 0`; #4 relee x5 del banco (ya escrito)                                               | ID/EX                                    |
| 7     | Forwarding MEM/WB            | `fwd_a = 00`, `fwd_b = 01` (#3 en WB, `rdW = x6`)                                              | Forwarding Unit, muxes de EX             |
| 7     | `beq` tomado                 | `pc_sel = 10`, `FlushD = 1`, `FlushE = 1` (x5 = x6 = `0x1F`)                                   | `branch_cmp`, `redirect_ex`, Hazard Unit |
| 8     | Búsqueda en el destino       | `pc_sel = 00`; IF busca `0x1C` (#8)                                                            | PC, IMEM                                 |
| 11    | HALT detectado en ID         | `halt_fetch = 1` (`StallF = 1`); lo buscado en `0x28` se descarta                              | Control, Hazard Unit                     |
| 14    | HALT en WB                   | `o_halted = 1`; pipeline vacío                                                                 | Fin de ejecución                         |

## 7. Cuenta de ciclos

```
instrucciones ejecutadas  =    7   (#1, #2, #3, #4, #8, #9, #10)
+ llenado                 =    4
+ stalls de load-use      =    1
+ 2 × branches tomados    =    2
---------------------------------
total                     =   14   (tiene que coincidir con el ciclo de o_halted en la carta)
```

## 8. Estado final

| Registro / dirección | Valor final  | ¿Lo escribió una instrucción descartada? (tiene que ser "no")          |
| -------------------- | ------------ | ---------------------------------------------------------------------- |
| x5                   | `0x0000001F` | No (#1). Si #5 se hubiera ejecutado, valdría `0x00000010`              |
| x6                   | `0x0000001F` | No (#3). #7 nunca se busca                                             |
| `M[0x00]`            | `0x0000001F` | No (#2)                                                                |
| `M[0x08]`            | `0x00000000` | No: nadie la escribe. Si #6 se hubiera ejecutado, valdría `0x00000010` |

Resto de los registros en 0. Memoria usada: 1 palabra (`0x00`).

Cuando esté el golden model (US-108), contrastar con `rvsim --expect`.
