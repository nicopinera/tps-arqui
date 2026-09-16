# TP2 - Arquitectura de Computadoras

- Krede, Julian
- Piñera, Nicolas

> [!NOTE]
> El baudrate generator es un contador sincrono cuya funcion principal es generar pulsos periodicos de habilitacion, llamados ticks a una frecuencia exacatmente 16 veces mayor que la tasa de baudios configurada para UART. El receptor UART necesita esta freceunca de sobremeustreo para poder estimar y muestrear con precision el punto medio de cada bit de datos recibido sin necesidad de transmitir una señar de reloj por la linea serie.
>
> $M=\frac{f_{clock}}{16 \cdot \text{Tasa de Baudios}}$
> la $f_{clock}=100MHz$
> la Tasa de Baudios = 19200 baudios
>
> Por lo tanto se neceista un contador modulo 326 que genere un pulso activo durante un ciclo de reloj cada 326 ciclos de reloj del sistema.
