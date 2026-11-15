`include "du_defs.vh"

// Debug Unit (US-403): interprete de comandos (du_cmd_fsm), respuestas cortas (du_resp_tx,
// canal 0 del mux), multiplexor de la UART de transmision (du_tx_mux), carga del programa
// (du_loader, US-404), control de ejecucion (du_exec_ctrl, US-406/407) y tramas largas
// SNAPSHOT y MEM_DATA (du_dumper, US-405/408, canal 1 del mux).
//
// Se conecta a la UART del top (recibe de uart_rx, transmite por uart_tx) y al nucleo con
// los puertos de docs/interfaces/riscv_core.md.
module debug_unit #(
    parameter CLK_FREQ_HZ       = 100_000_000,
    parameter RX_TIMEOUT_CYCLES = CLK_FREQ_HZ / 1000 * `DU_RX_TIMEOUT_MS,
    parameter IMEM_ADDR_BITS    = 8,
    parameter DMEM_ADDR_BITS    = 8
  )(
    input  wire        clock,
    input  wire        i_reset,

    // uart_rx
    input  wire        i_rx_done,
    input  wire [7:0]  i_rx_data,
    input  wire        i_parity_err,

    // uart_tx
    output wire        o_tx_start,
    output wire [7:0]  o_tx_data,
    input  wire        i_tx_done,

    // Nucleo: carga de la IMEM y limpieza (du_loader, docs/interfaces/riscv_core.md 2.2 y 2.3)
    output wire        o_imem_we,
    output wire [IMEM_ADDR_BITS-1:0] o_imem_addr,
    output wire [31:0] o_imem_wdata,
    output wire        o_dmem_we,
    output wire [DMEM_ADDR_BITS-1:0] o_dmem_addr,
    output wire        o_clear_used,
    output wire        o_flush_all,

    // Nucleo: ejecucion (du_exec_ctrl)
    output wire        o_enable,     // i_enable del nucleo: STEP = 1 ciclo, RUN = hasta o_halted
    output wire        o_stop_fetch, // i_stop_fetch del nucleo (ABORT, US-407)
    input  wire        i_halted,     // o_halted del nucleo
    input  wire        i_illegal,    // o_illegal del nucleo

    // Nucleo: lo que lee du_dumper para el SNAPSHOT y el MEM_DATA (riscv_core.md 2.4)
    input  wire [31:0] i_pc,                             // o_pc
    output wire [4:0]  o_dbg_reg_addr,                   // registro a leer (combinacional)
    input  wire [31:0] i_dbg_reg_data,
    output wire [DMEM_ADDR_BITS-1:0] o_dbg_mem_addr,     // palabra de DMEM a leer (combinacional)
    input  wire [31:0] i_dbg_mem_data,
    input  wire        i_dbg_mem_used,                   // bitmap de esa palabra
    input  wire [DMEM_ADDR_BITS:0] i_dbg_used_count,     // K: palabras escritas
    input  wire        i_stall,                          // senales de riesgo (byte 9)
    input  wire        i_flush_if_id,
    input  wire        i_flush_id_ex,
    input  wire [1:0]  i_fwd_a,
    input  wire [1:0]  i_fwd_b,
    input  wire [103:0] i_if_id,                         // latches (layout del snapshot)
    input  wire [247:0] i_id_ex,
    input  wire [151:0] i_ex_mem,
    input  wire [143:0] i_mem_wb,

    output wire [3:0]  o_estado
  );

  wire       w_resp_send, w_resp_done, w_tx_sel;
  wire [7:0] w_resp_tipo, w_resp_codigo;
  wire       w_start_0, w_done_0;
  wire [7:0] w_data_0;
  wire       w_req_load, w_load_byte, w_load_cancel, w_load_done, w_req_reset, w_reset_done;
  wire [7:0] w_load_data, w_load_err;
  wire       w_load_done_ex;                       // du_loader -> du_exec_ctrl: ciclos a 0
  wire       w_req_run, w_req_step, w_req_abort, w_step_done, w_run_fin;
  wire [31:0] w_ciclos;                            // du_exec_ctrl -> du_dumper
  wire       w_req_dump, w_req_dump_mem, w_dump_done;
  wire [15:0] w_dm_addr, w_dm_n;
  wire [7:0] w_snap_estado, w_dump_err;
  wire       w_start_1, w_done_1;
  wire [7:0] w_data_1;

  // Fin del drenado de ABORT: los 4 bits valid de los latches (riscv_core.md 4)
  wire [3:0] w_valid = {i_mem_wb[104], i_ex_mem[112], i_id_ex[200], i_if_id[96]};

  du_cmd_fsm #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ), .RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)
  ) u_cmd (
    .clock(clock), .i_reset(i_reset),
    .i_rx_done(i_rx_done), .i_rx_data(i_rx_data), .i_parity_err(i_parity_err),
    .o_resp_send(w_resp_send), .o_resp_tipo(w_resp_tipo), .o_resp_codigo(w_resp_codigo),
    .i_resp_done(w_resp_done),
    .o_tx_sel(w_tx_sel),
    .o_req_load(w_req_load), .o_load_byte(w_load_byte), .o_load_data(w_load_data),
    .o_load_cancel(w_load_cancel), .i_load_done(w_load_done), .i_load_err(w_load_err),
    .o_req_reset(w_req_reset), .i_reset_done(w_reset_done),
    .o_req_run(w_req_run), .o_req_step(w_req_step), .o_req_abort(w_req_abort),
    .i_step_done(w_step_done), .i_run_fin(w_run_fin),
    .i_halted(i_halted), .i_illegal(i_illegal),
    .o_req_dump(w_req_dump), .o_req_dump_mem(w_req_dump_mem),
    .o_dm_addr(w_dm_addr), .o_dm_n(w_dm_n),
    .i_dump_done(w_dump_done), .i_dump_err(w_dump_err), .o_snap_estado(w_snap_estado),
    .o_estado(o_estado)
  );

  du_loader #(
    .IMEM_ADDR_BITS(IMEM_ADDR_BITS), .DMEM_ADDR_BITS(DMEM_ADDR_BITS)
  ) u_loader (
    .clock(clock), .i_reset(i_reset),
    .i_req_load(w_req_load), .i_load_byte(w_load_byte), .i_load_data(w_load_data),
    .i_load_cancel(w_load_cancel), .o_done(w_load_done), .o_err(w_load_err),
    .i_req_reset(w_req_reset), .o_reset_done(w_reset_done),
    .o_imem_we(o_imem_we), .o_imem_addr(o_imem_addr), .o_imem_wdata(o_imem_wdata),
    .o_dmem_we(o_dmem_we), .o_dmem_addr(o_dmem_addr),
    .o_clear_used(o_clear_used), .o_flush_all(o_flush_all),
    .o_load_done(w_load_done_ex)
  );

  du_exec_ctrl u_exec (
    .clock(clock), .i_reset(i_reset),
    .i_req_run(w_req_run), .i_req_step(w_req_step), .i_req_abort(w_req_abort),
    .o_step_done(w_step_done), .o_run_fin(w_run_fin),
    .i_load_done(w_load_done_ex),
    .i_halted(i_halted), .i_valid(w_valid),
    .o_enable(o_enable), .o_stop_fetch(o_stop_fetch),
    .o_ciclos(w_ciclos)
  );

  du_dumper #(.DMEM_ADDR_BITS(DMEM_ADDR_BITS)) u_dumper (
    .clock(clock), .i_reset(i_reset),
    .i_req_dump(w_req_dump), .i_snap_estado(w_snap_estado),
    .i_req_dump_mem(w_req_dump_mem), .i_dm_addr(w_dm_addr), .i_dm_n(w_dm_n),
    .o_done(w_dump_done), .o_err(w_dump_err),
    .i_ciclos(w_ciclos), .i_pc(i_pc),
    .o_dbg_reg_addr(o_dbg_reg_addr), .i_dbg_reg_data(i_dbg_reg_data),
    .o_dbg_mem_addr(o_dbg_mem_addr), .i_dbg_mem_data(i_dbg_mem_data),
    .i_dbg_mem_used(i_dbg_mem_used), .i_dbg_used_count(i_dbg_used_count),
    .i_stall(i_stall), .i_flush_if_id(i_flush_if_id), .i_flush_id_ex(i_flush_id_ex),
    .i_fwd_a(i_fwd_a), .i_fwd_b(i_fwd_b),
    .i_if_id(i_if_id), .i_id_ex(i_id_ex), .i_ex_mem(i_ex_mem), .i_mem_wb(i_mem_wb),
    .o_tx_start(w_start_1), .o_tx_data(w_data_1), .i_tx_done(w_done_1)
  );

  du_resp_tx u_resp (
    .clock(clock), .i_reset(i_reset),
    .i_send(w_resp_send), .i_tipo(w_resp_tipo), .i_codigo(w_resp_codigo),
    .o_done(w_resp_done),
    .o_tx_start(w_start_0), .o_tx_data(w_data_0), .i_tx_done(w_done_0)
  );

  du_tx_mux u_mux (
    .i_sel(w_tx_sel),
    .i_start_0(w_start_0), .i_data_0(w_data_0), .o_done_0(w_done_0),
    .i_start_1(w_start_1), .i_data_1(w_data_1), .o_done_1(w_done_1),
    .o_tx_start(o_tx_start), .o_tx_data(o_tx_data), .i_tx_done(i_tx_done)
  );

endmodule
