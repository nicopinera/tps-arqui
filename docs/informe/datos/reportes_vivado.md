# Datos de Vivado del sistema completo

Generado por `tools/scripts/resumen_reportes.py` desde `hw/reports/`. No editar a mano: volver a correr `make impl`, `make freq-sweep` y `make reportes`.

## Resumen de timing (`top_timing_summary.rpt`)

| WNS (ns) | TNS (ns) | Endpoints que fallan (setup) | WHS (ns) | THS (ns) | Endpoints |
|---|---|---|---|---|---|
| 0.345 | 0.000 | 0 | 0.054 | 0.000 | 14525 |

## Los 10 peores caminos de setup (`top_timing_setup.rpt`)

| # | Slack (ns) | Origen | Destino | Retardo (ns) | Lógica / ruteo | Niveles | Skew (ns) |
|---|---|---|---|---|---|---|---|
| 1 | 0.345 | `u_du/u_dumper/r_pos_reg[3]/C` | `u_tx/datapath/o_p_reg_reg/D` | 11.226 | 38% / 62% | 15  (CARRY4=3 LUT2=1 LUT3=1 LUT5=3 LUT6=5 MUXF7=2) | -0.111 |
| 2 | 0.630 | `u_du/u_dumper/r_pos_reg[2]/C` | `u_tx/datapath/o_b_reg_reg[2]/D` | 10.940 | 40% / 60% | 15  (CARRY4=3 LUT3=2 LUT5=3 LUT6=4 MUXF7=2 RAMD64E=1) | -0.111 |
| 3 | 0.638 | `u_du/u_dumper/r_pos_reg[2]/C` | `u_du/u_dumper/r_xor_reg[1]/D` | 10.834 | 38% / 62% | 13  (CARRY4=3 LUT3=1 LUT4=1 LUT5=2 LUT6=3 MUXF7=2 RAMD64E=1) | -0.113 |
| 4 | 0.664 | `u_core/u_ex_mem_reg/o_rd_reg[2]/C` | `u_core/u_if_stage/r_pc_reg[0]/CE` | 10.556 | 24% / 76% | 12  (CARRY4=2 LUT2=1 LUT3=1 LUT4=1 LUT5=1 LUT6=6) | -0.227 |
| 5 | 0.673 | `u_core/u_ex_mem_reg/o_rd_reg[2]/C` | `u_core/u_if_stage/r_pc_reg[1]/CE` | 10.547 | 24% / 76% | 12  (CARRY4=2 LUT2=1 LUT3=1 LUT4=1 LUT5=1 LUT6=6) | -0.227 |
| 6 | 0.673 | `u_core/u_ex_mem_reg/o_rd_reg[2]/C` | `u_core/u_if_stage/r_pc_reg[8]/CE` | 10.547 | 24% / 76% | 12  (CARRY4=2 LUT2=1 LUT3=1 LUT4=1 LUT5=1 LUT6=6) | -0.227 |
| 7 | 0.684 | `u_du/u_dumper/r_pos_reg[2]/C` | `u_tx/datapath/o_b_reg_reg[5]/D` | 10.886 | 40% / 60% | 15  (CARRY4=3 LUT3=2 LUT5=4 LUT6=3 MUXF7=2 RAMD64E=1) | -0.112 |
| 8 | 0.734 | `u_core/u_ex_mem_reg/o_rd_reg[2]/C` | `u_core/u_if_id_reg/o_instr_reg[18]/R` | 10.195 | 25% / 75% | 12  (CARRY4=2 LUT3=1 LUT5=2 LUT6=7) | -0.294 |
| 9 | 0.752 | `u_core/u_ex_mem_reg/o_rd_reg[2]/C` | `u_core/u_if_id_reg/o_instr_reg[10]/R` | 10.177 | 25% / 75% | 12  (CARRY4=2 LUT3=1 LUT5=2 LUT6=7) | -0.294 |
| 10 | 0.752 | `u_core/u_ex_mem_reg/o_rd_reg[2]/C` | `u_core/u_if_id_reg/o_instr_reg[19]/R` | 10.177 | 25% / 75% | 12  (CARRY4=2 LUT3=1 LUT5=2 LUT6=7) | -0.294 |

### El peor camino de setup, tramo por tramo

| Tramo | Tipo | Retardo (ns) | Celda o red |
|---|---|---|---|
| logica | FDRE | 0.419 | `u_du/u_dumper/r_pos_reg[3]/Q` |
| ruteo | net (fo=7) | 0.561 | `u_du/u_dumper/r_pos_reg_n_0_[3]` |
| logica | CARRY4 | 0.571 | `u_du/u_dumper/w_off_carry/CO[3]` |
| ruteo | net (fo=1) | 0.000 | `u_du/u_dumper/w_off_carry_n_0` |
| logica | CARRY4 | 0.334 | `u_du/u_dumper/w_off_carry__0/O[1]` |
| ruteo | net (fo=26) | 0.521 | `u_du/u_dumper/w_off_carry__0_n_6` |
| logica | LUT2 | 0.303 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_6/O` |
| ruteo | net (fo=8) | 0.588 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_6_n_0` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_2/O` |
| ruteo | net (fo=1) | 0.000 | `u_du/u_dumper/w_mem_addr_dm_carry__0_i_2_n_0` |
| logica | CARRY4 | 0.248 | `u_du/u_dumper/w_mem_addr_dm_carry__0/O[2]` |
| ruteo | net (fo=2) | 0.653 | `u_du/u_dumper/w_mem_addr_dm[6]` |
| logica | LUT3 | 0.331 | `u_du/u_dumper/r_mem_reg_r2_0_127_6_6_i_8/O` |
| ruteo | net (fo=16) | 0.729 | `u_core/u_mem_stage/u_data_mem/r_mem_reg_r2_128_255_23_23/DPRA6` |
| logica | MUXF7 | 0.495 | `u_core/u_mem_stage/u_data_mem/r_mem_reg_r2_128_255_23_23/F7.DP/O` |
| ruteo | net (fo=1) | 0.584 | `u_du/u_dumper/r_xor[7]_i_109_4` |
| logica | LUT5 | 0.297 | `u_du/u_dumper/r_xor[7]_i_69/O` |
| ruteo | net (fo=2) | 0.665 | `u_du/u_dumper/w_mem_data[23]` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/r_xor[7]_i_109/O` |
| ruteo | net (fo=1) | 0.467 | `u_du/u_dumper/r_xor[7]_i_109_n_0` |
| logica | LUT5 | 0.124 | `u_du/u_dumper/r_xor[7]_i_64/O` |
| ruteo | net (fo=1) | 0.000 | `u_du/u_dumper/r_xor[7]_i_64_n_0` |
| logica | MUXF7 | 0.212 | `u_du/u_dumper/r_xor_reg[7]_i_36/O` |
| ruteo | net (fo=1) | 0.493 | `u_du/u_dumper/r_xor_reg[7]_i_36_n_0` |
| logica | LUT6 | 0.299 | `u_du/u_dumper/r_xor[7]_i_16/O` |
| ruteo | net (fo=1) | 0.453 | `u_du/u_dumper/r_xor[7]_i_16_n_0` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/r_xor[7]_i_7/O` |
| ruteo | net (fo=3) | 0.833 | `u_du/u_dumper/r_modo_reg_0` |
| logica | LUT5 | 0.124 | `u_du/u_dumper/o_p_reg_i_2/O` |
| ruteo | net (fo=1) | 0.425 | `u_du/u_dumper/o_p_reg_i_2_n_0` |
| logica | LUT6 | 0.124 | `u_du/u_dumper/o_p_reg_i_1/O` |
| ruteo | net (fo=1) | 0.000 | `u_tx/datapath/o_p_reg_reg_0` |

Lógica: 4.253 ns · ruteo: 6.973 ns · requerido: 11.765 ns · skew: -0.111 ns

## Los 10 peores caminos de hold (`top_timing_hold.rpt`)

| # | Slack (ns) | Origen | Destino | Retardo (ns) | Lógica / ruteo | Niveles | Skew (ns) |
|---|---|---|---|---|---|---|---|
| 1 | 0.054 | `u_core/u_mem_wb_reg/o_pc_plus4_reg[8]/C` | `u_du/u_dumper/r_latches_reg[576]/D` | 0.387 | 36% / 64% | 0 | 0.264 |
| 2 | 0.057 | `u_core/u_mem_wb_reg/o_alu_result_reg[10]/C` | `u_du/u_dumper/r_latches_reg[514]/D` | 0.394 | 36% / 64% | 0 | 0.265 |
| 3 | 0.060 | `u_core/u_id_ex_reg/o_instr_reg[24]/C` | `u_du/u_dumper/r_latches_reg[344]/D` | 0.391 | 36% / 64% | 0 | 0.265 |
| 4 | 0.061 | `u_core/u_id_ex_reg/o_instr_reg[17]/C` | `u_core/u_ex_mem_reg/o_instr_reg[17]/D` | 0.400 | 35% / 65% | 0 | 0.264 |
| 5 | 0.062 | `u_core/u_ex_mem_reg/o_store_data_reg[26]/C` | `u_du/u_dumper/r_latches_reg[410]/D` | 0.392 | 36% / 64% | 0 | 0.264 |
| 6 | 0.062 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_0_63_30_31/RAMA/WADR0` | 0.643 | 22% / 78% | 0 | 0.271 |
| 7 | 0.062 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_0_63_30_31/RAMB/WADR0` | 0.643 | 22% / 78% | 0 | 0.271 |
| 8 | 0.062 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_0_63_30_31/RAMC/WADR0` | 0.643 | 22% / 78% | 0 | 0.271 |
| 9 | 0.062 | `u_du/u_loader/o_imem_addr_reg[0]/C` | `u_core/u_if_stage/u_instr_mem/r_mem_reg_0_63_30_31/RAMD/WADR0` | 0.643 | 22% / 78% | 0 | 0.271 |
| 10 | 0.063 | `u_core/u_id_ex_reg/o_pc_reg[23]/C` | `u_du/u_dumper/r_latches_reg[127]/D` | 0.264 | 48% / 52% | 0 | 0.184 |

## Barrido de frecuencia (`freq_sweep.csv`)

| MHz | Período (ns) | WNS (ns) | WHS (ns) | TNS (ns) | Cumple (WNS ≥ 0.3, WHS ≥ 0) |
|---|---|---|---|---|---|
| 50 | 20.000 | 4.760 | 0.057 | 0.000 | si |
| 75 | 13.333 | 0.635 | 0.049 | 0.000 | si |
| 80 | 12.500 | 0.688 | 0.069 | 0.000 | si |
| 85 | 11.765 | 0.324 | 0.049 | 0.000 | si |
| 90 | 11.111 | 0.028 | 0.047 | 0.000 | no |
| 95 | 10.526 | -0.306 | 0.049 | -0.494 | no |
| 100 | 10.000 | -1.145 | 0.039 | -8.953 | no |

Frecuencia óptima según ADR-016: **85 MHz**.

## Rendimiento (`docs/informe/datos/cpi.csv`)

| Programa | Ciclos | Instrucciones | CPI | Stalls | Control | % perdidos | Tiempo a 85 MHz (µs) |
|---|---|---|---|---|---|---|---|
| demos/burbuja | 383 | 270 | 1.419 | 28 | 81 | 28.5 | 4.51 |
| demos/copia_cadena | 122 | 92 | 1.326 | 12 | 14 | 21.3 | 1.44 |
| demos/factorial | 232 | 164 | 1.415 | 0 | 64 | 27.6 | 2.73 |
| demos/fibonacci | 188 | 145 | 1.297 | 0 | 39 | 20.7 | 2.21 |
| demos/hola | 130 | 96 | 1.354 | 14 | 16 | 23.1 | 1.53 |
| demos/subrutina | 381 | 309 | 1.233 | 0 | 68 | 17.8 | 4.48 |
| demos/suma_arreglo | 88 | 61 | 1.443 | 8 | 15 | 26.1 | 1.04 |
| riesgos/01_forwarding_ex_mem | 7 | 2 | 3.500 | 0 | 1 | 14.3 | 0.08 |
| riesgos/02_forwarding_mem_wb | 8 | 3 | 2.667 | 0 | 1 | 12.5 | 0.09 |
| riesgos/03_distancia_3_banco | 9 | 4 | 2.250 | 0 | 1 | 11.1 | 0.11 |
| riesgos/04_forwarding_el_mas_nuevo | 8 | 3 | 2.667 | 0 | 1 | 12.5 | 0.09 |
| riesgos/05_forwarding_store | 7 | 2 | 3.500 | 0 | 1 | 14.3 | 0.08 |
| riesgos/06_load_use_stall | 10 | 4 | 2.500 | 1 | 1 | 20.0 | 0.12 |
| riesgos/07_load_use_evitado | 10 | 5 | 2.000 | 0 | 1 | 10.0 | 0.12 |
| riesgos/08_branch_tomado_flush | 10 | 3 | 3.333 | 0 | 3 | 30.0 | 0.12 |
| riesgos/09_branch_no_tomado | 8 | 3 | 2.667 | 0 | 1 | 12.5 | 0.09 |
| riesgos/10_jal_flush | 8 | 2 | 4.000 | 0 | 2 | 25.0 | 0.09 |
| riesgos/11_jalr_flush | 10 | 3 | 3.333 | 0 | 3 | 30.0 | 0.12 |
| riesgos/12_load_use_y_branch | 13 | 5 | 2.600 | 1 | 3 | 30.8 | 0.15 |
| special/ilegal | 6 | 1 | 6.000 | 0 | 1 | 16.7 | 0.07 |
| special/illegal | 8 | 3 | 2.667 | 0 | 1 | 12.5 | 0.09 |
| special/no_halt | 8 | 3 | 2.667 | 0 | 1 | 12.5 | 0.09 |
| tests/h2/branches | 69 | 52 | 1.327 | 0 | 13 | 18.8 | 0.81 |
| tests/h2/i_arith | 21 | 16 | 1.312 | 0 | 1 | 4.8 | 0.25 |
| tests/h2/illegal | 11 | 6 | 1.833 | 0 | 1 | 9.1 | 0.13 |
| tests/h2/jumps | 30 | 18 | 1.667 | 0 | 8 | 26.7 | 0.35 |
| tests/h2/loads_stores | 36 | 31 | 1.161 | 0 | 1 | 2.8 | 0.42 |
| tests/h2/lui | 16 | 11 | 1.455 | 0 | 1 | 6.2 | 0.19 |
| tests/h2/r_type | 28 | 23 | 1.217 | 0 | 1 | 3.6 | 0.33 |
| tests/h2/shifts | 21 | 16 | 1.312 | 0 | 1 | 4.8 | 0.25 |
| tests/hazards/branch_after_load | 38 | 24 | 1.583 | 4 | 6 | 26.3 | 0.45 |
| tests/hazards/branch_not_taken | 28 | 22 | 1.273 | 0 | 2 | 7.1 | 0.33 |
| tests/hazards/branch_taken | 49 | 31 | 1.581 | 1 | 13 | 28.6 | 0.58 |
| tests/hazards/fwd_branch | 50 | 34 | 1.471 | 0 | 12 | 24.0 | 0.59 |
| tests/hazards/fwd_doble | 29 | 24 | 1.208 | 0 | 1 | 3.4 | 0.34 |
| tests/hazards/fwd_ex_mem | 43 | 38 | 1.132 | 0 | 1 | 2.3 | 0.51 |
| tests/hazards/fwd_mem_wb | 34 | 29 | 1.172 | 0 | 1 | 2.9 | 0.40 |
| tests/hazards/fwd_store_data | 39 | 34 | 1.147 | 0 | 1 | 2.6 | 0.46 |
| tests/hazards/halt_after_branch | 24 | 15 | 1.600 | 0 | 5 | 20.8 | 0.28 |
| tests/hazards/halt_speculative | 35 | 22 | 1.591 | 0 | 9 | 25.7 | 0.41 |
| tests/hazards/illegal_speculative | 21 | 13 | 1.615 | 0 | 4 | 19.0 | 0.25 |
| tests/hazards/jal_branch_same_cycle | 26 | 16 | 1.625 | 0 | 6 | 23.1 | 0.31 |
| tests/hazards/jal_jalr | 24 | 15 | 1.600 | 0 | 5 | 20.8 | 0.28 |
| tests/hazards/load_use | 55 | 45 | 1.222 | 5 | 1 | 10.9 | 0.65 |
| tests/hazards/load_use_store | 43 | 33 | 1.303 | 5 | 1 | 14.0 | 0.51 |
| tests/hazards/x0_no_forward | 23 | 17 | 1.353 | 1 | 1 | 8.7 | 0.27 |
| tests/instr/branches | 57 | 38 | 1.500 | 0 | 15 | 26.3 | 0.67 |
| tests/instr/i_arith | 49 | 44 | 1.114 | 0 | 1 | 2.0 | 0.58 |
| tests/instr/i_logic | 43 | 38 | 1.132 | 0 | 1 | 2.3 | 0.51 |
| tests/instr/i_shift | 40 | 35 | 1.143 | 0 | 1 | 2.5 | 0.47 |
| tests/instr/jal | 29 | 19 | 1.526 | 0 | 6 | 20.7 | 0.34 |
| tests/instr/jalr | 48 | 29 | 1.655 | 0 | 15 | 31.2 | 0.56 |
| tests/instr/loads | 77 | 68 | 1.132 | 4 | 1 | 6.5 | 0.91 |
| tests/instr/lui | 40 | 35 | 1.143 | 0 | 1 | 2.5 | 0.47 |
| tests/instr/misaligned | 42 | 34 | 1.235 | 3 | 1 | 9.5 | 0.49 |
| tests/instr/r_arith | 51 | 46 | 1.109 | 0 | 1 | 2.0 | 0.60 |
| tests/instr/r_logic | 41 | 36 | 1.139 | 0 | 1 | 2.4 | 0.48 |
| tests/instr/r_shift | 47 | 42 | 1.119 | 0 | 1 | 2.1 | 0.55 |
| tests/instr/stores | 57 | 49 | 1.163 | 3 | 1 | 7.0 | 0.67 |

Total de 59 programas: 3068 ciclos, 2281 instrucciones, CPI agregado 1.345; ciclos perdidos por load-use 90 (2.9 %), por control 461 (15.0 %), llenado 236.

## Recursos (`top_util.rpt`)

| Recurso | Usado | Disponible | % |
|---|---|---|---|
| Slice LUTs | 3945 | 20800 | 18.97 |
| LUT as Logic | 3257 | 20800 | 15.66 |
| LUT as Memory | 688 | 9600 | 7.17 |
| Slice Registers | 2975 | 41600 | 7.15 |
| F7 Muxes | 608 | 16300 | 3.73 |
| F8 Muxes | 147 | 8150 | 1.80 |
| Block RAM Tile | 0 | 50 | 0.00 |
| DSPs | 0 | 90 | 0.00 |
| Bonded IOB | 8 | 106 | 7.55 |
| BUFGCTRL | 2 | 32 | 6.25 |

## Recursos por módulo (`top_util_hier.rpt`)

| Instancia | Módulo | LUTs | LUTs lógica | LUTRAM | SRL | FF | RAMB36 | RAMB18 | DSP |
|---|---|---|---|---|---|---|---|---|---|
| `top` | (top) | 3945 | 3257 | 688 | 0 | 2975 | 0 | 0 | 0 |
| `  (top)` | (top) | 1 | 1 | 0 | 0 | 8 | 0 | 0 | 0 |
| `  u_core` | riscv_core | 3082 | 2394 | 688 | 0 | 1916 | 0 | 0 | 0 |
| `    u_mem_wb_reg` | mem_wb_reg | 350 | 350 | 0 | 0 | 139 | 0 | 0 | 0 |
| `    u_ex_mem_reg` | ex_mem_reg | 336 | 336 | 0 | 0 | 157 | 0 | 0 | 0 |
| `    u_id_ex_reg` | id_ex_reg | 401 | 401 | 0 | 0 | 223 | 0 | 0 | 0 |
| `    u_id_stage` | id_stage | 890 | 890 | 0 | 0 | 992 | 0 | 0 | 0 |
| `      u_reg_file` | reg_file | 890 | 890 | 0 | 0 | 992 | 0 | 0 | 0 |
| `    u_if_id_reg` | if_id_reg | 123 | 123 | 0 | 0 | 105 | 0 | 0 | 0 |
| `    u_if_stage` | if_stage | 226 | 50 | 176 | 0 | 32 | 0 | 0 | 0 |
| `      u_instr_mem` | instr_mem | 217 | 41 | 176 | 0 | 0 | 0 | 0 | 0 |
| `    u_mem_stage` | mem_stage | 732 | 220 | 512 | 0 | 265 | 0 | 0 | 0 |
| `      u_data_mem` | data_mem | 568 | 56 | 512 | 0 | 0 | 0 | 0 | 0 |
| `      u_dmem_bitmap` | dmem_bitmap | 164 | 164 | 0 | 0 | 265 | 0 | 0 | 0 |
| `  u_du` | debug_unit | 783 | 783 | 0 | 0 | 1001 | 0 | 0 | 0 |
| `    u_cmd` | du_cmd_fsm | 110 | 110 | 0 | 0 | 100 | 0 | 0 | 0 |
| `    u_dumper` | du_dumper | 532 | 532 | 0 | 0 | 721 | 0 | 0 | 0 |
| `    u_loader` | du_loader | 108 | 108 | 0 | 0 | 130 | 0 | 0 | 0 |
| `  u_rx` | uart_rx | 58 | 58 | 0 | 0 | 21 | 0 | 0 | 0 |
| `    datapath` | uart_rx_datapath | 56 | 56 | 0 | 0 | 16 | 0 | 0 | 0 |

## Potencia (`top_power.rpt`)

| Concepto | Valor |
|---|---|
| Total On-Chip Power (W) | 0.210 |
| Dynamic (W) | 0.138 |
| Device Static (W) | 0.072 |
| Junction Temperature (C) | 26.1 |
| Clocks | 0.007 |
| Slice Logic | 0.002 |
| Signals | 0.004 |
| LUT as Distributed RAM | <0.001 |
| I/O | 0.002 |
| MMCM | 0.122 |

Estimación vectorless de Vivado (sin actividad simulada): sirve para comparar, no como medición.
