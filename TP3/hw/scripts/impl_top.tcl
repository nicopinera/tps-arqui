# Sintesis, implementacion y bitstream del sistema completo (top: UART + Debug Unit + nucleo)
# para la Basys 3, con todos los reportes del Hito 6 (US-601 timing y skew, US-603 metricas).
#
# A diferencia de synth_du_ooc.tcl y timing_core_ooc.tcl, esto es EN CONTEXTO: con los pines
# reales y el reloj de la placa, asi que el camino critico es el del sistema (incluidos los que
# cruzan de la Debug Unit al nucleo, que los analisis fuera de contexto no ven).
#
# El reloj del sistema sale del Clock Wizard (hw/ip/clk_wiz_0, gen_clk_wiz.tcl): Vivado deriva
# solo el reloj generado a partir del de 100 MHz del .xdc, asi que el timing ya es a la
# frecuencia de trabajo. Para medir otras frecuencias sin MMCM: freq_sweep.tcl.
#
# Uso (desde TP3/, en la "Vivado 2025.2 Tcl Shell" o con vivado en el PATH):
#   cd build/vivado_top && vivado -mode batch -nojournal -nolog -source ../../hw/scripts/impl_top.tcl
#   (desde otra carpeta Vivado deja ahi sus archivos sueltos: clockInfo.txt, etc.)
#   o desde WSL:  make impl
#
# Salidas:
#   hw/reports/top_*.rpt          reportes (se versionan, ADR-016)
#   build/vivado_top/top.bit      bitstream (no se versiona: se rearma con este script)
#   build/vivado_top/*.dcp        checkpoints para abrir en la GUI (open_checkpoint)
#   build/vivado_top/commit.txt   commit del que salio el bitstream (US-411 AC4)
# Codigo de salida: 0 si WNS y WHS son >= 0, 1 si no se cumple el reloj.

source [file join [file dirname [info script]] comun.tcl]

set OUT     [file join $RAIZ build vivado_top]
file mkdir $OUT
file mkdir $REP

# --- Sintesis ----------------------------------------------------------------------------------
set_part $PARTE
leer_fuentes $RAIZ
# El IP se regenera desde el .xci (lo unico versionado) en build/, para no ensuciar hw/ip/
set DIR_IP [file join $OUT ip]
file delete -force $DIR_IP
file mkdir $DIR_IP
file copy [file join $RAIZ hw ip clk_wiz_0] $DIR_IP
read_ip [file join $DIR_IP clk_wiz_0 clk_wiz_0.xci]
generate_target all [get_ips clk_wiz_0]
synth_ip [get_ips clk_wiz_0]
synth_design -top top -part $PARTE -include_dirs [includes $RAIZ]
write_checkpoint -force [file join $OUT top_synth.dcp]

# --- Implementacion ----------------------------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $OUT top_routed.dcp]

# --- Reportes ----------------------------------------------------------------------------------
# Timing (US-601): resumen con Check Timing, los 10 peores de setup y de hold (con el skew de
# cada camino en "Clock Path Skew"), y la red del reloj.
report_timing_summary -max_paths 10 -report_unconstrained -check_timing_verbose \
                      -file [file join $REP top_timing_summary.rpt]
report_timing -max_paths 10 -nworst 1 -sort_by slack -setup -input_pins \
              -file [file join $REP top_timing_setup.rpt]
report_timing -max_paths 10 -nworst 1 -sort_by slack -hold -input_pins \
              -file [file join $REP top_timing_hold.rpt]
report_clock_networks    -file [file join $REP top_clock_networks.rpt]
report_clock_utilization -file [file join $REP top_clock_utilization.rpt]
# Metricas (US-603): recursos totales y por modulo, potencia.
report_utilization               -file [file join $REP top_util.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $REP top_util_hier.rpt]
report_power                     -file [file join $REP top_power.rpt]
report_drc                       -file [file join $REP top_drc.rpt]
foreach r [glob [file join $REP top_*.rpt]] { limpiar_reporte $r $RAIZ }

# --- Bitstream ---------------------------------------------------------------------------------
write_bitstream -force [file join $OUT top.bit]
set commit "desconocido"
catch { set commit [exec git -C $RAIZ rev-parse --short HEAD] }
set cambios ""
catch { if {[exec git -C $RAIZ status --porcelain -- hw] ne ""} { set cambios " (con cambios sin commitear en hw/)" } }
set fh [open [file join $OUT commit.txt] w]
puts $fh "$commit$cambios"
close $fh

# --- Resumen en la consola -----------------------------------------------------------------------
set w [wns]
set h [whs]
set reloj [get_clocks -of_objects [get_pins u_clk/clk_out1]]
set periodo [get_property PERIOD $reloj]
puts [format "\ntop en contexto, reloj %s de %.3f ns (%.1f MHz)" $reloj $periodo [expr {1000.0 / $periodo}]]
puts "  WNS (setup) = $w ns   WHS (hold) = $h ns   latches = [llength [all_latches]]"
puts "  Bitstream: $OUT/top.bit (commit $commit$cambios)"
puts "  Reportes en $REP/top_*.rpt"

if {$w < 0 || $h < 0} {
    puts "ATENCION: no se cumple el reloj"
    exit 1
}
exit 0
