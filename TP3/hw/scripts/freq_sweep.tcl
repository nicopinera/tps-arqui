# Barrido de frecuencia del sistema completo (US-602, ADR-016): implementa el top con varios
# periodos de reloj y anota WNS/WHS/TNS de cada uno. La frecuencia optima es la mayor con
# WNS >= 0,3 ns y WHS >= 0 (criterio de ADR-016).
#
# La sintesis se hace una sola vez (con el reloj de 10 ns del .xdc) y cada frecuencia parte de
# ese checkpoint: solo cambia el reloj para place & route. Es lo habitual para un barrido; a
# frecuencias altas puede quedar un poco pesimista, porque la sintesis no apunto a ese reloj.
#
# Uso (desde TP3/):
#   cd build/vivado_sweep && vivado -mode batch -nojournal -nolog -source ../../hw/scripts/freq_sweep.tcl
#   vivado ... -source hw/scripts/freq_sweep.tcl -tclargs 50 100 150     (otras frecuencias, MHz)
#   o desde WSL:  make freq-sweep
#
# Salida: hw/reports/freq_sweep.csv (mhz,periodo_ns,wns_ns,whs_ns,tns_ns,cumple) y el log.
# Tarda ~5 minutos por frecuencia.

source [file join [file dirname [info script]] comun.tcl]

set FRECUENCIAS [expr {[llength $argv] > 0 ? $argv : {50 75 100 110 125 140 150}}]
set MARGEN_WNS  0.3   ;# ADR-016
set OUT [file join $RAIZ build vivado_sweep]
file mkdir $OUT
file mkdir $REP

set_part $PARTE
leer_fuentes $RAIZ
# Sin el MMCM: el reloj de la placa entra directo y cada corrida le cambia el periodo
synth_design -top top -part $PARTE -include_dirs [includes $RAIZ] -verilog_define SIN_MMCM
set SYNTH [file join $OUT top_synth.dcp]
write_checkpoint -force $SYNTH
close_design

set csv [file join $REP freq_sweep.csv]
set fh [open $csv w]
puts $fh "mhz,periodo_ns,wns_ns,whs_ns,tns_ns,cumple"
close $fh

foreach mhz $FRECUENCIAS {
    set periodo [format "%.3f" [expr {1000.0 / $mhz}]]
    open_checkpoint $SYNTH
    create_clock -name sys_clk_pin -period $periodo [get_ports clock]
    opt_design
    place_design
    phys_opt_design
    route_design
    set w [wns]
    set h [whs]
    # TNS = suma de los slacks negativos, un camino por endpoint (como el resumen de Vivado)
    set tns 0.0
    foreach p [get_timing_paths -setup -max_paths 100000 -nworst 1 -slack_lesser_than 0 -quiet] {
        set tns [expr {$tns + [get_property SLACK $p]}]
    }
    set cumple [expr {$w >= $MARGEN_WNS && $h >= 0 ? "si" : "no"}]
    set fh [open $csv a]
    puts $fh [format "%s,%s,%.3f,%.3f,%.3f,%s" $mhz $periodo $w $h $tns $cumple]
    close $fh
    puts [format "\n>>> %s MHz (%s ns): WNS = %.3f  WHS = %.3f  TNS = %.3f  cumple ADR-016: %s\n" \
              $mhz $periodo $w $h $tns $cumple]
    close_design
}

puts "\nBarrido en $csv"
exit 0
