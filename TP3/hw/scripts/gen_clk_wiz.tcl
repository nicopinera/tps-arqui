# Genera el Clock Wizard (MMCM) que lleva el reloj de la placa (100 MHz) a la frecuencia de
# trabajo del sistema (US-602, ADR-016). Escribe TP3/hw/ip/clk_wiz_0/clk_wiz_0.xci, que es lo
# unico que se versiona (ADR-020); impl_top.tcl regenera el resto a partir de el.
#
# Uso (desde TP3/build/, con vivado en el PATH):
#   vivado -mode batch -nojournal -nolog -source ../hw/scripts/gen_clk_wiz.tcl -tclargs 85
# El argumento es la frecuencia de salida en MHz. Tiene que coincidir con CLK_FREQ_HZ de
# hw/rtl/top.v (de ahi salen el baud rate de la UART y el timeout de la Debug Unit).

source [file join [file dirname [info script]] comun.tcl]

set MHZ    [expr {[llength $argv] > 0 ? [lindex $argv 0] : 85}]
set DIR_IP [file join $RAIZ hw ip]
file delete -force [file join $DIR_IP clk_wiz_0]
file mkdir $DIR_IP

create_project -in_memory -part $PARTE
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0 -dir $DIR_IP
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ                {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  $MHZ \
    CONFIG.USE_RESET                   {false} \
    CONFIG.USE_LOCKED                  {true} \
] [get_ips clk_wiz_0]

# La frecuencia que sale de verdad: 100 * M / (D * O) con los divisores que eligio el wizard
set real "?"
catch {
    set ip [get_ips clk_wiz_0]
    set m [get_property CONFIG.MMCM_CLKFBOUT_MULT_F $ip]
    set d [get_property CONFIG.MMCM_DIVCLK_DIVIDE $ip]
    set o [get_property CONFIG.MMCM_CLKOUT0_DIVIDE_F $ip]
    set real [format "%.3f (M = %s, D = %s, O = %s)" [expr {100.0 * $m / ($d * $o)}] $m $d $o]
}
puts "\nclk_wiz_0: 100 MHz -> pedidos $MHZ MHz, sale $real MHz"
puts "  [file join $DIR_IP clk_wiz_0 clk_wiz_0.xci]"
exit 0
