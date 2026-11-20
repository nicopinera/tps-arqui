# Cosas que comparten impl_top.tcl y freq_sweep.tcl.

set RAIZ   [file normalize [file join [file dirname [info script]] .. ..]]
set PARTE  xc7a35tcpg236-1
set REP    [file join $RAIZ hw reports]

# Lee el RTL sintetizable (todo hw/rtl salvo legacy/) y las constraints de la placa.
proc leer_fuentes {raiz} {
    foreach dir {core debug uart} {
        foreach f [lsort [glob [file join $raiz hw rtl $dir *.v]]] { read_verilog $f }
    }
    read_verilog [file join $raiz hw rtl top.v]
    read_xdc [file join $raiz hw constraints basys3.xdc]
}

# Los .vh (du_defs.vh, latches) estan en estas carpetas.
proc includes {raiz} {
    return [list [file join $raiz hw rtl debug] [file join $raiz hw rtl core]]
}

# Los reportes se versionan: se saca el nombre de la maquina, la fecha y la ruta del repo, asi
# un reporte nuevo solo cambia en git si cambio el diseno.
proc limpiar_reporte {archivo raiz} {
    set fh [open $archivo r]
    set texto [read $fh]
    close $fh
    regsub -all -line {^(\| Host\s*:).*$} $texto {\1 -} texto
    regsub -all -line {^(\| Date\s*:).*$} $texto {\1 -} texto
    set texto [string map [list $raiz TP3] $texto]
    set fh [open $archivo w]
    puts -nonewline $fh $texto
    close $fh
}

# WNS y WHS del diseno abierto (el peor camino de setup y de hold).
proc wns {} { return [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] }
proc whs {} { return [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]] }
