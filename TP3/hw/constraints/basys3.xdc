## Basys3 rev B - Constraints del TP3 (top.v, US-401)
## Basado en el .xdc general de Digilent, dejando solo los pines usados.
## Uso:
##   La placa se comunica con la PC por el mismo cable micro-USB de
##   programacion (puente USB-UART FTDI FT2232HQ, aparece como COMx o /dev/ttyUSBx).
##   Trama: 19200 baudios, 8 bits de datos, paridad par, 1 bit de stop (8E1, ADR-002).
##   btnC (centro) = reset sincrono

## ============================================================
## Clock (100 MHz)
## ============================================================
set_property -dict { PACKAGE_PIN W5    IOSTANDARD LVCMOS33 } [get_ports clock]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock]

## ============================================================
## USB-RS232 (puente FTDI)
##   RsRx (B18): PC -> FPGA  -> entrada rx
##   RsTx (A18): FPGA -> PC  -> salida tx
## ============================================================
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports rx]
set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports tx]

## rx es asincrona al clock: la toma el sincronizador de 2 FF (r_rx_meta/r_rx_sync, ASYNC_REG)
## del top, asi que no hay camino de timing que analizar desde el pin (US-401, AC3).
set_false_path -from [get_ports rx]

## ============================================================
## LEDs de estado (LD3..LD0) -> o_led[3:0]
##   LD0 = READY, LD1 = RUN, LD2 = HALTED (Debug Unit, US-403)
##   LD3 = hubo un error de paridad desde el ultimo reset
## ============================================================
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {o_led[0]}]
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {o_led[1]}]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {o_led[2]}]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {o_led[3]}]

## ============================================================
## Boton central (btnC) -> i_reset
## ============================================================
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports i_reset]

## ============================================================
## Opciones de configuracion (validas para cualquier diseño)
## ============================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
