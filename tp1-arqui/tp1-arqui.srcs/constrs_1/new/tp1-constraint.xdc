set_property PACKAGE_PIN W5 [get_ports clk] # Vincula el puerto fisico W5 (donde esta el clock) a mi puerto clk
set_property IOSTANDARD LVCMOS33 [get_ports clk] # Define el estandar electrico (3.3V)
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk] # Crea el clock de 10ns