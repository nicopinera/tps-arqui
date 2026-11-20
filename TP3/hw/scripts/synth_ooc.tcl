# Sintesis fuera de contexto (out of context) de los modulos de hw/rtl/core con Vivado en
# modo batch. Cada modulo se sintetiza solo, sin top ni restricciones de pines: sirve para ver
# recursos (LUTs, LUTRAM, flip-flops, BRAM) y confirmar que no se infieren latches, antes de
# que exista riscv_core. No mide timing (eso necesita el diseno completo y el .xdc, US-601).
#
# Uso (desde TP3/):  make synth-ooc [MOD="alu data_mem"]
#   o directamente:  vivado -mode batch -nojournal -nolog -source hw/scripts/synth_ooc.tcl \
#                           -tclargs [modulo ...]
# Sin modulos, sintetiza todos los .v de hw/rtl/core.
#
# Salida en build/synth/: util_<modulo>.rpt (reporte completo de Vivado) y resumen.txt (tabla).
# Codigo de salida: 0 si ningun modulo tiene latches ni critical warnings, 1 si alguno tiene.

# Rutas relativas a TP3/ (la carpeta dos niveles arriba de este script), asi el script anda
# desde cualquier directorio. make synth-ooc lo corre desde build/synth para que los archivos
# temporales de Vivado (.Xil/, logs) queden ahi.
set RAIZ     [file normalize [file join [file dirname [info script]] .. ..]]
set PARTE    xc7a35tcpg236-1
set DIR_RTL  $RAIZ/hw/rtl/core
set INCLUDES [list $RAIZ/hw/rtl/core $RAIZ/hw/rtl/debug]
set DIR_OUT  $RAIZ/build/synth

file mkdir $DIR_OUT

set fuentes [lsort [glob $DIR_RTL/*.v]]
if {[llength $argv] > 0} {
    set modulos $argv
} else {
    set modulos {}
    foreach f $fuentes { lappend modulos [file rootname [file tail $f]] }
}

# Devuelve el valor de la columna "Used" de una fila del reporte de utilizacion.
proc usado {reporte fila} {
    if {[regexp "\\|\\s*${fila}\\s*\\|\\s*(\\d+)" $reporte -> valor]} { return $valor }
    return 0
}

set_part $PARTE
foreach f $fuentes { read_verilog $f }

set filas {}
set con_problemas 0
foreach top $modulos {
    set criticos_antes [get_msg_config -count -severity {CRITICAL WARNING}]
    synth_design -top $top -part $PARTE -mode out_of_context -include_dirs $INCLUDES
    set criticos [expr {[get_msg_config -count -severity {CRITICAL WARNING}] - $criticos_antes}]

    set reporte [report_utilization -return_string]
    set fh [open $DIR_OUT/util_$top.rpt w]
    puts $fh $reporte
    close $fh

    set luts    [usado $reporte {Slice LUTs\*?}]
    set lutram  [usado $reporte {LUT as Distributed RAM}]
    set ffs     [usado $reporte {Register as Flip Flop}]
    set latches [usado $reporte {Register as Latch}]
    set bram    [usado $reporte {Block RAM Tile}]
    if {$latches > 0 || $criticos > 0} { incr con_problemas }
    lappend filas [format "%-14s %6s %7s %6s %8s %5s %9s" \
        $top $luts $lutram $ffs $latches $bram $criticos]
}

set encabezado [format "%-14s %6s %7s %6s %8s %5s %9s" \
    Modulo LUTs LUTRAM FF Latches BRAM Criticos]
set resumen "Sintesis fuera de contexto ($PARTE)\n\n$encabezado\n[join $filas \n]\n"
set fh [open $DIR_OUT/resumen.txt w]
puts -nonewline $fh $resumen
close $fh

puts "\n$resumen"
puts "Reportes completos en $DIR_OUT/util_<modulo>.rpt"
if {$con_problemas > 0} {
    puts "ATENCION: $con_problemas modulo(s) con latches o critical warnings"
    exit 1
}
exit 0
