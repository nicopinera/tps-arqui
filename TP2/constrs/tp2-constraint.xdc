## Basys3 rev B - Constraints para el TP2 (UART + ALU)
## Basado en el .xdc general de Digilent, dejando solo los pines usados.
## Uso:
##   La placa se comunica con la PC por el mismo cable micro-USB de
##   programacion (puente USB-UART FTDI FT2232HQ, aparece como /dev/ttyUSBx).
##   Trama: 19200 baudios, 8 bits de datos, paridad par, 1 bit de stop (8E1).
##   Se envian 3 bytes: A, B, OPCODE -> la placa responde 1 byte con el resultado.
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

## ============================================================
## LEDs del resultado (LD7..LD0) -> o_led[7:0]
## ============================================================
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {o_led[0]}]
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {o_led[1]}]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {o_led[2]}]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {o_led[3]}]
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports {o_led[4]}]
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports {o_led[5]}]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports {o_led[6]}]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {o_led[7]}]

## ============================================================
## LEDs de flags
##   LD15 -> o_zero
##   LD14 -> o_overflow
## ============================================================
set_property -dict { PACKAGE_PIN L1    IOSTANDARD LVCMOS33 } [get_ports o_zero]
set_property -dict { PACKAGE_PIN P1    IOSTANDARD LVCMOS33 } [get_ports o_overflow]

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
