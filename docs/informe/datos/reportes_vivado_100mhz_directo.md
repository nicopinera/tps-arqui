# Datos de Vivado del sistema completo

Generado por `tools/scripts/resumen_reportes.py` desde `reports/antes_100mhz/`. No editar a mano: volver a correr `make impl`, `make freq-sweep` y `make reportes`.

## Resumen de timing (`top_timing_summary.rpt`)

| WNS (ns) | TNS (ns) | Endpoints que fallan (setup) | WHS (ns) | THS (ns) | Endpoints |
|---|---|---|---|---|---|
| -1.316 | -18.849 | 76 | 0.039 | 0.000 | 14528 |

## Los 10 peores caminos de setup (`top_timing_setup.rpt`)

| # | Slack (ns) | Origen | Destino | Retardo (ns) | Lógica / ruteo | Niveles | Skew (ns) |
|---|---|---|---|---|---|---|---|
| 1 | -1.316 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_tx/datapath/o_p_reg_reg/D` | 11.276 | 36% / 64% | 14  (CARRY4=2 LUT1=1 LUT2=1 LUT3=1 LUT5=2 LUT6=5 MUXF7=2) | -0.034 |
| 2 | -0.839 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_tx/datapath/o_b_reg_reg[2]/D` | 10.801 | 41% / 59% | 17  (CARRY4=4 LUT1=1 LUT3=2 LUT5=3 LUT6=4 MUXF7=2 RAMD64E=1) | -0.034 |
| 3 | -0.763 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_tx/datapath/o_b_reg_reg[0]/D` | 10.722 | 37% / 63% | 13  (CARRY4=2 LUT1=1 LUT2=1 LUT3=1 LUT5=2 LUT6=4 MUXF7=2) | -0.034 |
| 4 | -0.761 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_du/u_dumper/r_xor_reg[0]/D` | 10.723 | 37% / 63% | 13  (CARRY4=2 LUT1=1 LUT2=1 LUT3=1 LUT4=1 LUT5=1 LUT6=4 MUXF7=2) | -0.032 |
| 5 | -0.574 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_tx/datapath/o_b_reg_reg[5]/D` | 10.538 | 40% / 60% | 15  (CARRY4=2 LUT1=1 LUT2=1 LUT3=2 LUT5=3 LUT6=4 MUXF7=2) | -0.032 |
| 6 | -0.574 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_tx/datapath/o_b_reg_reg[1]/D` | 10.532 | 40% / 60% | 15  (CARRY4=4 LUT1=1 LUT3=1 LUT5=4 LUT6=2 MUXF7=2 RAMD64E=1) | -0.038 |
| 7 | -0.490 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_du/u_dumper/r_xor_reg[2]/D` | 10.453 | 39% / 61% | 16  (CARRY4=4 LUT1=1 LUT3=1 LUT4=1 LUT5=5 LUT6=2 MUXF7=1 RAMD64E=1) | -0.034 |
| 8 | -0.465 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_tx/datapath/o_b_reg_reg[3]/D` | 10.428 | 39% / 61% | 16  (CARRY4=4 LUT1=1 LUT3=1 LUT4=1 LUT5=4 LUT6=3 MUXF7=1 RAMD64E=1) | -0.034 |
| 9 | -0.443 | `u_core/u_mem_wb_reg/o_rd_reg[1]/C` | `u_core/u_if_stage/r_pc_reg[2]/D` | 10.314 | 17% / 83% | 9  (LUT2=1 LUT3=1 LUT6=7) | -0.047 |
| 10 | -0.407 | `u_du/u_dumper/r_pos_reg[2]_replica/C` | `u_du/u_dumper/r_xor_reg[3]/D` | 10.370 | 39% / 61% | 16  (CARRY4=4 LUT1=1 LUT3=1 LUT4=1 LUT5=4 LUT6=3 MUXF7=1 RAMD64E=1) | -0.034 |

### El peor camino de setup, tramo por tramo

| Tramo | Tipo | Retardo (ns) | Celda o red |
|---|---|---|---|
| logica | FDRE | 0.456 | `u_du/u_dumper/r_pos_reg[2]_replica/Q` |
| ruteo | net (fo=2) | 0.589 | `u_du/u_dumper/r_pos_reg_n_0_[2]_repN` |
| logica | LUT1 | 0.124 | `u_du/u_dumper/w_off_carry_i_3/O` |
| ruteo | net (fo=1) | 0.000 | `u_du/u_dumper/w_off_carry_i_3_n_0` |
| logica | CARRY4 | 0.580 | `u_du/u_dumper/w_off_carry/O[2]` |
| ruteo | net (fo=66) | 0.594 | `u_du/u_dumper/w_off_carry_n_5` |
| logica | LUT2 | 0.302 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_7/O` |
| ruteo | net (fo=3) | 0.431 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_7_n_0` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_3/O` |
| ruteo | net (fo=1) | 0.000 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_3_n_0` |
| logica | CARRY4 | 0.580 | `u_du/u_dumper/w_mem_addr_dm_carry__0/O[2]` |
| ruteo | net (fo=2) | 0.556 | `u_du/u_dumper/w_mem_addr_dm[6]` |
| logica | LUT3 | 0.302 | `u_du/u_dumper/r_mem_reg_r2_0_127_0_0_i_8/O` |
| ruteo | net (fo=50) | 1.143 | `u_core/u_mem_stage/u_data_mem/r_mem_reg_r2_0_127_16_16/DPRA6` |
| logica | MUXF7 | 0.292 | `u_core/u_mem_stage/u_data_mem/r_mem_reg_r2_0_127_16_16/F7.DP/O` |
| ruteo | net (fo=1) | 0.934 | `u_du/u_dumper/r_xor[0]_i_69_5` |
| logica | LUT5 | 0.297 | `u_du/u_dumper/r_xor[0]_i_46/O` |
| ruteo | net (fo=2) | 0.676 | `u_du/u_dumper/w_mem_data[16]` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/r_xor[0]_i_24/O` |
| ruteo | net (fo=1) | 0.000 | `u_du/u_dumper/r_xor[0]_i_24_n_0` |
| logica | MUXF7 | 0.217 | `u_du/u_dumper/r_xor_reg[0]_i_9/O` |
| ruteo | net (fo=1) | 0.581 | `u_du/u_dumper/r_xor_reg[0]_i_9_n_0` |
| logica | LUT6 | 0.299 | `u_du/u_dumper/r_xor[0]_i_3/O` |
| ruteo | net (fo=1) | 0.713 | `u_du/u_dumper/r_xor[0]_i_3_n_0` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/r_xor[0]_i_2/O` |
| ruteo | net (fo=3) | 0.326 | `u_du/u_resp/o_p_reg_reg_0` |
| logica | LUT5 | 0.124 | `u_du/u_resp/o_p_reg_i_3/O` |
| ruteo | net (fo=1) | 0.664 | `u_du/u_dumper/o_p_reg_reg_0` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/o_p_reg_i_1/O` |
| ruteo | net (fo=1) | 0.000 | `u_tx/datapath/o_p_reg_reg_0` |

Lógica: 4.069 ns · ruteo: 7.207 ns · requerido: 10.000 ns · skew: -0.034 ns

## Los 10 peores caminos de hold (`top_timing_hold.rpt`)

| # | Slack (ns) | Origen | Destino | Retardo (ns) | Lógica / ruteo | Niveles | Skew (ns) |
|---|---|---|---|---|---|---|---|
| 1 | 0.039 | `u_core/u_mem_wb_reg/o_mem_data_reg[8]/C` | `u_du/u_dumper/r_latches_reg[544]/D` | 0.371 | 38% / 62% | 0 | 0.266 |
| 2 | 0.059 | `u_core/u_mem_wb_reg/o_pc_plus4_reg[21]/C` | `u_du/u_dumper/r_latches_reg[589]/D` | 0.394 | 36% / 64% | 0 | 0.264 |
| 3 | 0.059 | `u_core/u_mem_wb_reg/o_mem_data_reg[0]/C` | `u_du/u_dumper/r_latches_reg[536]/D` | 0.395 | 36% / 64% | 0 | 0.266 |
| 4 | 0.061 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_21_23/RAMA/WADR0` | 0.384 | 37% / 63% | 0 | 0.013 |
| 5 | 0.061 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_21_23/RAMB/WADR0` | 0.384 | 37% / 63% | 0 | 0.013 |
| 6 | 0.061 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_21_23/RAMC/WADR0` | 0.384 | 37% / 63% | 0 | 0.013 |
| 7 | 0.061 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_21_23/RAMD/WADR0` | 0.384 | 37% / 63% | 0 | 0.013 |
| 8 | 0.065 | `u_du/u_loader/o_imem_addr_reg[1]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_30_31/RAMA/WADR1` | 0.388 | 36% / 64% | 0 | 0.014 |
| 9 | 0.065 | `u_du/u_loader/o_imem_addr_reg[1]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_30_31/RAMB/WADR1` | 0.388 | 36% / 64% | 0 | 0.014 |
| 10 | 0.065 | `u_du/u_loader/o_imem_addr_reg[1]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_128_191_30_31/RAMC/WADR1` | 0.388 | 36% / 64% | 0 | 0.014 |

## Barrido de frecuencia (`freq_sweep.csv`)

_Falta `freq_sweep.csv`: correr `make freq-sweep` desde TP3/._

## Rendimiento (`docs/informe/datos/cpi.csv`)

| Programa | Ciclos | Instrucciones | CPI | Stalls | Control | % perdidos |
|---|---|---|---|---|---|---|
| demos/burbuja | 383 | 270 | 1.419 | 28 | 81 | 28.5 |
| demos/copia_cadena | 122 | 92 | 1.326 | 12 | 14 | 21.3 |
| demos/factorial | 232 | 164 | 1.415 | 0 | 64 | 27.6 |
| demos/fibonacci | 188 | 145 | 1.297 | 0 | 39 | 20.7 |
| demos/hola | 130 | 96 | 1.354 | 14 | 16 | 23.1 |
| demos/subrutina | 381 | 309 | 1.233 | 0 | 68 | 17.8 |
| demos/suma_arreglo | 88 | 61 | 1.443 | 8 | 15 | 26.1 |
| riesgos/01_forwarding_ex_mem | 7 | 2 | 3.500 | 0 | 1 | 14.3 |
| riesgos/02_forwarding_mem_wb | 8 | 3 | 2.667 | 0 | 1 | 12.5 |
| riesgos/03_distancia_3_banco | 9 | 4 | 2.250 | 0 | 1 | 11.1 |
| riesgos/04_forwarding_el_mas_nuevo | 8 | 3 | 2.667 | 0 | 1 | 12.5 |
| riesgos/05_forwarding_store | 7 | 2 | 3.500 | 0 | 1 | 14.3 |
| riesgos/06_load_use_stall | 10 | 4 | 2.500 | 1 | 1 | 20.0 |
| riesgos/07_load_use_evitado | 10 | 5 | 2.000 | 0 | 1 | 10.0 |
| riesgos/08_branch_tomado_flush | 10 | 3 | 3.333 | 0 | 3 | 30.0 |
| riesgos/09_branch_no_tomado | 8 | 3 | 2.667 | 0 | 1 | 12.5 |
| riesgos/10_jal_flush | 8 | 2 | 4.000 | 0 | 2 | 25.0 |
| riesgos/11_jalr_flush | 10 | 3 | 3.333 | 0 | 3 | 30.0 |
| riesgos/12_load_use_y_branch | 13 | 5 | 2.600 | 1 | 3 | 30.8 |
| special/ilegal | 6 | 1 | 6.000 | 0 | 1 | 16.7 |
| special/illegal | 8 | 3 | 2.667 | 0 | 1 | 12.5 |
| special/no_halt | 8 | 3 | 2.667 | 0 | 1 | 12.5 |
| tests/h2/branches | 69 | 52 | 1.327 | 0 | 13 | 18.8 |
| tests/h2/i_arith | 21 | 16 | 1.312 | 0 | 1 | 4.8 |
| tests/h2/illegal | 11 | 6 | 1.833 | 0 | 1 | 9.1 |
| tests/h2/jumps | 30 | 18 | 1.667 | 0 | 8 | 26.7 |
| tests/h2/loads_stores | 36 | 31 | 1.161 | 0 | 1 | 2.8 |
| tests/h2/lui | 16 | 11 | 1.455 | 0 | 1 | 6.2 |
| tests/h2/r_type | 28 | 23 | 1.217 | 0 | 1 | 3.6 |
| tests/h2/shifts | 21 | 16 | 1.312 | 0 | 1 | 4.8 |
| tests/hazards/branch_after_load | 38 | 24 | 1.583 | 4 | 6 | 26.3 |
| tests/hazards/branch_not_taken | 28 | 22 | 1.273 | 0 | 2 | 7.1 |
| tests/hazards/branch_taken | 49 | 31 | 1.581 | 1 | 13 | 28.6 |
| tests/hazards/fwd_branch | 50 | 34 | 1.471 | 0 | 12 | 24.0 |
| tests/hazards/fwd_doble | 29 | 24 | 1.208 | 0 | 1 | 3.4 |
| tests/hazards/fwd_ex_mem | 43 | 38 | 1.132 | 0 | 1 | 2.3 |
| tests/hazards/fwd_mem_wb | 34 | 29 | 1.172 | 0 | 1 | 2.9 |
| tests/hazards/fwd_store_data | 39 | 34 | 1.147 | 0 | 1 | 2.6 |
| tests/hazards/halt_after_branch | 24 | 15 | 1.600 | 0 | 5 | 20.8 |
| tests/hazards/halt_speculative | 35 | 22 | 1.591 | 0 | 9 | 25.7 |
| tests/hazards/illegal_speculative | 21 | 13 | 1.615 | 0 | 4 | 19.0 |
| tests/hazards/jal_branch_same_cycle | 26 | 16 | 1.625 | 0 | 6 | 23.1 |
| tests/hazards/jal_jalr | 24 | 15 | 1.600 | 0 | 5 | 20.8 |
| tests/hazards/load_use | 55 | 45 | 1.222 | 5 | 1 | 10.9 |
| tests/hazards/load_use_store | 43 | 33 | 1.303 | 5 | 1 | 14.0 |
| tests/hazards/x0_no_forward | 23 | 17 | 1.353 | 1 | 1 | 8.7 |
| tests/instr/branches | 57 | 38 | 1.500 | 0 | 15 | 26.3 |
| tests/instr/i_arith | 49 | 44 | 1.114 | 0 | 1 | 2.0 |
| tests/instr/i_logic | 43 | 38 | 1.132 | 0 | 1 | 2.3 |
| tests/instr/i_shift | 40 | 35 | 1.143 | 0 | 1 | 2.5 |
| tests/instr/jal | 29 | 19 | 1.526 | 0 | 6 | 20.7 |
| tests/instr/jalr | 48 | 29 | 1.655 | 0 | 15 | 31.2 |
| tests/instr/loads | 77 | 68 | 1.132 | 4 | 1 | 6.5 |
| tests/instr/lui | 40 | 35 | 1.143 | 0 | 1 | 2.5 |
| tests/instr/misaligned | 42 | 34 | 1.235 | 3 | 1 | 9.5 |
| tests/instr/r_arith | 51 | 46 | 1.109 | 0 | 1 | 2.0 |
| tests/instr/r_logic | 41 | 36 | 1.139 | 0 | 1 | 2.4 |
| tests/instr/r_shift | 47 | 42 | 1.119 | 0 | 1 | 2.1 |
| tests/instr/stores | 57 | 49 | 1.163 | 3 | 1 | 7.0 |

Total de 59 programas: 3068 ciclos, 2281 instrucciones, CPI agregado 1.345; ciclos perdidos por load-use 90 (2.9 %), por control 461 (15.0 %), llenado 236.

## Recursos (`top_util.rpt`)

| Recurso | Usado | Disponible | % |
|---|---|---|---|
| Slice LUTs | 3950 | 20800 | 18.99 |
| LUT as Logic | 3262 | 20800 | 15.68 |
| LUT as Memory | 688 | 9600 | 7.17 |
| Slice Registers | 2976 | 41600 | 7.15 |
| F7 Muxes | 612 | 16300 | 3.75 |
| F8 Muxes | 147 | 8150 | 1.80 |
| Block RAM Tile | 0 | 50 | 0.00 |
| DSPs | 0 | 90 | 0.00 |
| Bonded IOB | 8 | 106 | 7.55 |
| BUFGCTRL | 1 | 32 | 3.13 |

## Recursos por módulo (`top_util_hier.rpt`)

| Instancia | Módulo | LUTs | LUTs lógica | LUTRAM | SRL | FF | RAMB36 | RAMB18 | DSP |
|---|---|---|---|---|---|---|---|---|---|
| `top` | (top) | 3950 | 3262 | 688 | 0 | 2976 | 0 | 0 | 0 |
| `  (top)` | (top) | 0 | 0 | 0 | 0 | 8 | 0 | 0 | 0 |
| `  u_core` | riscv_core | 3087 | 2399 | 688 | 0 | 1916 | 0 | 0 | 0 |
| `    u_mem_wb_reg` | mem_wb_reg | 351 | 351 | 0 | 0 | 139 | 0 | 0 | 0 |
| `    u_ex_mem_reg` | ex_mem_reg | 336 | 336 | 0 | 0 | 157 | 0 | 0 | 0 |
| `    u_id_ex_reg` | id_ex_reg | 404 | 404 | 0 | 0 | 223 | 0 | 0 | 0 |
| `    u_id_stage` | id_stage | 889 | 889 | 0 | 0 | 992 | 0 | 0 | 0 |
| `      u_reg_file` | reg_file | 889 | 889 | 0 | 0 | 992 | 0 | 0 | 0 |
| `    u_if_id_reg` | if_id_reg | 125 | 125 | 0 | 0 | 105 | 0 | 0 | 0 |
| `    u_if_stage` | if_stage | 226 | 50 | 176 | 0 | 32 | 0 | 0 | 0 |
| `      u_instr_mem` | instr_mem | 217 | 41 | 176 | 0 | 0 | 0 | 0 | 0 |
| `    u_mem_stage` | mem_stage | 732 | 220 | 512 | 0 | 265 | 0 | 0 | 0 |
| `      u_data_mem` | data_mem | 568 | 56 | 512 | 0 | 0 | 0 | 0 | 0 |
| `      u_dmem_bitmap` | dmem_bitmap | 164 | 164 | 0 | 0 | 265 | 0 | 0 | 0 |
| `  u_du` | debug_unit | 783 | 783 | 0 | 0 | 1002 | 0 | 0 | 0 |
| `    u_cmd` | du_cmd_fsm | 112 | 112 | 0 | 0 | 100 | 0 | 0 | 0 |
| `    u_dumper` | du_dumper | 530 | 530 | 0 | 0 | 722 | 0 | 0 | 0 |
| `    u_loader` | du_loader | 108 | 108 | 0 | 0 | 130 | 0 | 0 | 0 |
| `  u_rx` | uart_rx | 59 | 59 | 0 | 0 | 21 | 0 | 0 | 0 |
| `    datapath` | uart_rx_datapath | 57 | 57 | 0 | 0 | 16 | 0 | 0 | 0 |

## Potencia (`top_power.rpt`)

| Concepto | Valor |
|---|---|
| Total On-Chip Power (W) | 0.094 |
| Dynamic (W) | 0.022 |
| Device Static (W) | 0.072 |
| Junction Temperature (C) | 25.5 |
| Clocks | 0.008 |
| Slice Logic | 0.004 |
| Signals | 0.008 |
| LUT as Distributed RAM | <0.001 |
| I/O | 0.002 |

Estimación vectorless de Vivado (sin actividad simulada): sirve para comparar, no como medición.
