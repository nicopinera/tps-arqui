# Restricciones de la Debug Unit sintetizada sola (out-of-context, synth_du_ooc.tcl).
# Solo el reloj: 100 MHz como en la placa. Sin pines (la DU no es el top: va adentro del
# top junto con el nucleo), asi que los caminos que entran o salen por puertos no se miden.
create_clock -period 10.000 -name clock [get_ports clock]
