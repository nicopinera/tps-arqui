# Sintesis e implementacion fuera de contexto (out of context) de riscv_core a 100 MHz, para
# tener el primer dato de timing del nucleo (US-210 AC5, ADR-016).
#
# Fuera de contexto porque los buses de depuracion del nucleo tienen mas bits que pines la
# Basys 3: Vivado no pone buffers de E/S y mide los caminos internos (registro a registro).
# Los puertos no tienen retardos de entrada/salida: esos caminos quedan sin restriccion hasta
# que exista el top con la Debug Unit (US-601).
#
# Uso (desde TP3/):  make timing-core
#   o directamente:  vivado -mode batch -nojournal -nolog -source hw/scripts/timing_core_ooc.tcl
#
# Salida: hw/reports/timing_core_ooc.rpt (resumen de timing) y util_core_ooc.rpt (recursos).
# Codigo de salida: 0 si WNS y WHS son >= 0, 1 si no se cumple el reloj.

set RAIZ     [file normalize [file join [file dirname [info script]] .. ..]]
set PARTE    xc7a35tcpg236-1
set PERIODO  10.000
set INCLUDES [list $RAIZ/hw/rtl/core $RAIZ/hw/rtl/debug]
set DIR_OUT  $RAIZ/hw/reports

file mkdir $DIR_OUT

set_part $PARTE
foreach f [lsort [glob $RAIZ/hw/rtl/core/*.v]] { read_verilog $f }

synth_design -top riscv_core -part $PARTE -mode out_of_context -include_dirs $INCLUDES
create_clock -name clock -period $PERIODO [get_ports clock]

opt_design
place_design
route_design

report_timing_summary -max_paths 10 -file $DIR_OUT/timing_core_ooc.rpt
report_utilization -file $DIR_OUT/util_core_ooc.rpt

# Los reportes se versionan: se saca el nombre de la maquina y la ruta absoluta del repo.
proc limpiar_reporte {archivo raiz} {
    set fh [open $archivo r]
    set texto [read $fh]
    close $fh
    regsub -all -line {^(\| Host\s*:).*$} $texto {\1 -} texto
    set texto [string map [list $raiz TP3] $texto]
    set fh [open $archivo w]
    puts -nonewline $fh $texto
    close $fh
}
limpiar_reporte $DIR_OUT/timing_core_ooc.rpt $RAIZ
limpiar_reporte $DIR_OUT/util_core_ooc.rpt $RAIZ

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts [format "\nriscv_core fuera de contexto, reloj de %.1f ns (%.0f MHz)" $PERIODO [expr {1000.0 / $PERIODO}]]
puts "  WNS = $wns ns   WHS = $whs ns"
puts "Reportes en $DIR_OUT/timing_core_ooc.rpt y util_core_ooc.rpt"

if {$wns < 0 || $whs < 0} {
    puts "ATENCION: no se cumple el reloj"
    exit 1
}
exit 0
