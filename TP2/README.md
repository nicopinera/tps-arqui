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

Para conectar el módulo `uart_rx` con la ALU y transmitir el resultado por `uart_tx`, la mejor estrategia de arquitectura es diseñar una **interfaz de control con máquina de estados (FSMD)**.

Como la UART envía y recibe datos de manera secuencial (byte a byte), la interfaz se encargará de actuar como "recopilador", almacenando los tres bytes entrantes en registros temporales antes de activar la ALU y mandar la orden de transmisión.

La interfaz debe pasar secuencialmente por los siguientes estados:

1. **WAIT_A**: Espera a que el receptor `uart_rx` indique que recibió el primer byte (`rx_done_tick` activo). Al recibirlo, guarda `rx_data` en un registro para el **Operando A**.
2. **WAIT_B**: Espera la llegada del segundo byte. Al activarse `rx_done_tick`, guarda `rx_data` en el registro para el **Operando B**.
3. **WAIT_OP**: Espera el tercer byte. Al llegar `rx_done_tick`, toma los 6 bits menos significativos (`rx_data[5:0]`), ignorando/truncando los 2 bits más significativos, y los guarda en el registro de **Opcode**.
4. **START_TX**: Con los operandos listos en la ALU, envía un pulso de un ciclo de reloj a `tx_start` para que `uart_tx` capture el resultado de la ALU (`alu_result`) y empiece a transmitirlo.
5. **WAIT_TX**: Espera a que el transmisor finalice la transmisión (`tx_done_tick`) y regresa al estado inicial `WAIT_A` para quedar listo para la siguiente operación.
