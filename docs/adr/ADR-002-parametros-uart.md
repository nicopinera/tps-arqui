# ADR-002 — Parámetros de la UART

- **Estado:** Aprobado
- **Fecha:** 2026-10-04
- **Autores:** Krede, Julián · Piñera, Nicolás
- **Bloquea:** US-401
- **Relacionados:** ADR-003 (checksum), ADR-008 (tamaño del volcado de memoria), ADR-016 (frecuencia de reloj)

## Contexto

Los módulos `uart_rx` y `uart_tx` del TP2 están verificados en placa con estos parámetros:

- 19200 bps, 8 bits de datos, paridad par, 1 bit de stop (trama de 11 bits).
- La paridad se **recibe pero no se valida**.
- `COUNT_MAX = 326` está fijo para un reloj de 100 MHz (sobremuestreo ×16).

El enunciado no dice si hay que mantener esos parámetros. La velocidad del enlace determina cuánto tarda cada snapshot y cada carga de programa:

| Operación                                   | Bytes aprox. | 19200 bps (~1745 B/s) | 115200 bps (~10 470 B/s) |
| ------------------------------------------- | ------------ | --------------------- | ------------------------ |
| Snapshot sin memoria                        | ~221 B       | ~130 ms               | ~21 ms                   |
| Snapshot con DMEM completa usada (256 pal.) | ~1760 B      | ~1,0 s                | ~0,17 s                  |
| `LOAD` de 256 instrucciones                 | ~1030 B      | ~0,6 s                | ~0,1 s                   |

## Decisión

1. **Velocidad: se mantiene 19200 bps**, igual que en el TP2.
2. **Trama: 8 bits de datos, paridad par, 1 bit de stop**, sin cambios.
3. **La paridad se valida en recepción.** Si un byte llega con la paridad incorrecta:
   - se descarta (no se entrega a la Debug Unit como dato válido),
   - `uart_rx` levanta una señal de error de paridad (`o_parity_err`),
   - la Debug Unit aborta el comando en curso y responde `NACK` con un código de error de paridad (se define en `docs/protocolo.md`, US-104).
4. **`COUNT_MAX` pasa a ser un parámetro calculado**, no un número fijo:
   `COUNT_MAX = round(CLK_FREQ_HZ / (16 × BAUD))`, con `CLK_FREQ_HZ` y `BAUD` como parámetros del `top`. Así la UART sigue andando si se cambia la frecuencia. El error de baud resultante tiene que ser < 2 %.

## Consecuencias

**Positivas:**

- La migración del TP2 no cambia el comportamiento eléctrico ni temporal de la UART: se reutiliza tal cual y solo se agrega la validación de paridad.
- Los errores de transmisión se detectan en dos niveles: paridad por byte y checksum por trama.
- La UART deja de depender de que el reloj sea de 100 MHz.

**Negativas:**

- Un snapshot con toda la DMEM usada tarda ~1 s y queda **en el límite de NFR-4**. El caso típico (~221 B + pocas palabras) sí cumple. Si las demos lo necesitan, se reevalúa subir a 115200 bps.
- El historial del paso a paso en la GUI se siente más lento que con 115200 bps.

**Restricciones que impone:**

- `uart_rx` agrega la salida `o_parity_err`; la Debug Unit tiene que manejarla en todos sus estados de recepción.
- `docs/protocolo.md` define un código de `NACK` para errores de paridad.
- El software de PC abre el puerto con `baudrate=19200, parity=PARITY_EVEN, stopbits=1, bytesize=8`.
- Si cambia `BAUD` o `CLK_FREQ_HZ`, se repite la prueba de eco de US-401 en placa antes de seguir.
