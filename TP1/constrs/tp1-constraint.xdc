## Basys3 rev B - Constraints para el TP1 (ALU + top)
## Basado en el .xdc general de Digilent, dejando solo los pines usados.
## Uso:
##   1) Poner el valor en SW7..SW0
##   2) Encender SW13 para cargar A, SW14 para B, SW15 para el opcode
##      (uno solo por vez; el resto apagado)
##   3) Apagar el selector. El resultado queda en LD7..LD0
##   btnC (centro) = reset sincrono

## ============================================================
## Clock (100 MHz)
## ============================================================
set_property -dict { PACKAGE_PIN W5    IOSTANDARD LVCMOS33 } [get_ports clock]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock]

## ============================================================
## Switches de datos: i_datos[7:0] -> SW7..SW0
## SW7 = MSB, SW0 = LSB
## ============================================================
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {i_datos[0]}]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {i_datos[1]}]
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports {i_datos[2]}]
set_property -dict { PACKAGE_PIN W17   IOSTANDARD LVCMOS33 } [get_ports {i_datos[3]}]
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports {i_datos[4]}]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports {i_datos[5]}]
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {i_datos[6]}]
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {i_datos[7]}]

## ============================================================
## Switches selectores: i_abc[2:0] -> SW15, SW14, SW13
##   SW13 (i_abc = 3'b001) -> carga A
##   SW14 (i_abc = 3'b010) -> carga B
##   SW15 (i_abc = 3'b100) -> carga opcode
## ============================================================
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports {i_abc[0]}]
set_property -dict { PACKAGE_PIN T1    IOSTANDARD LVCMOS33 } [get_ports {i_abc[1]}]
set_property -dict { PACKAGE_PIN R2    IOSTANDARD LVCMOS33 } [get_ports {i_abc[2]}]

## ============================================================
## LEDs de resultado: o_led[7:0] -> LD7..LD0
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
