# Sintesis e implementacion out-of-context (OOC) de la Debug Unit para la Basys 3.
#
# OOC = el modulo se sintetiza como un bloque que despues va adentro de otro: sin pines.
# debug_unit no puede ser el top (sus ~800 bits de puertos no entran en los pines de la
# placa), pero asi se ve si es sintetizable, cuanto ocupa y si sus caminos internos
# (registro -> registro) cumplen 100 MHz.
#
# Uso (desde la carpeta TP3, en la "Vivado 2025.2 Tcl Shell" o con vivado en el PATH):
#   vivado -mode batch -source hw/scripts/synth_du_ooc.tcl
#
# Salidas:
#   hw/reports/du_ooc_*.rpt         reportes (se versionan, ADR-016)
#   build/vivado_du_ooc/*.dcp       checkpoints para abrir en la GUI (no se versionan)

set ROOT [file normalize [file join [file dirname [info script]] .. ..]]
set OUT  [file join $ROOT build vivado_du_ooc]
set REP  [file join $ROOT hw reports]
set PART xc7a35tcpg236-1
file mkdir $OUT
file mkdir $REP

# --- Fuentes ---------------------------------------------------------------------------------
read_verilog [glob [file join $ROOT hw rtl debug *.v]]
read_xdc -mode out_of_context [file join $ROOT hw constraints du_ooc.xdc]

# --- Sintesis --------------------------------------------------------------------------------
synth_design -top debug_unit -part $PART -mode out_of_context \
             -include_dirs [file join $ROOT hw rtl debug]
write_checkpoint -force [file join $OUT du_synth.dcp]
report_utilization -hierarchical -file [file join $REP du_ooc_util_synth.rpt]

# --- Implementacion (place & route) ----------------------------------------------------------
opt_design
place_design
route_design
write_checkpoint -force [file join $OUT du_routed.dcp]

report_utilization              -file [file join $REP du_ooc_util.rpt]
report_utilization -hierarchical -file [file join $REP du_ooc_util_hier.rpt]
report_timing_summary -max_paths 10 -file [file join $REP du_ooc_timing_summary.rpt]
report_timing -max_paths 10 -sort_by slack -file [file join $REP du_ooc_timing_setup.rpt]
report_timing -max_paths 10 -sort_by slack -delay_type min -file [file join $REP du_ooc_timing_hold.rpt]

# --- Resumen en la consola ---------------------------------------------------------------------
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
set latches [llength [all_latches]]
puts ""
puts "================ debug_unit OOC @ 100 MHz ================"
puts "  WNS (setup) = $wns ns    (>= 0: cumple)"
puts "  WHS (hold)  = $whs ns    (>= 0: cumple)"
puts "  Latches     = $latches     (tiene que ser 0)"
puts "  Reportes en $REP"
puts "=========================================================="
