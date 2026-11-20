`include "du_defs.vh"

// Top de la Basys 3 (US-401, US-411): la PC habla por la UART con la Debug Unit, que carga,
// ejecuta y vuelca el estado del nucleo.
//
//   rx -> sincronizador -> uart_rx -> debug_unit -> uart_tx -> tx
//                                         |   ^
//                     carga, enable, flush |   | PC, registros, DMEM, latches, riesgos
//                                         v   |
//                                       riscv_core
//
// Un solo reloj para todo: el nucleo se detiene con i_enable, nunca cortando el reloj
// (ADR-001). Los puertos entre la Debug Unit y el nucleo son los de
// docs/interfaces/riscv_core.md.
//
// Reloj (US-602, ADR-016): el sistema no cierra timing a 100 MHz, asi que un Clock Wizard
// (MMCM, hw/ip/clk_wiz_0) genera CLK_FREQ_HZ desde los 100 MHz de la placa, por la red
// dedicada de reloj (no es "intervenir el clock": no hay logica en el camino del reloj).
// El MMCM solo se instancia al sintetizar (Vivado define SYNTHESIS): en Icarus y Verilator
// el reloj del testbench entra directo. SIN_MMCM lo saca tambien en sintesis (freq_sweep.tcl
// barre frecuencias con el reloj de la placa).
module top #(
    parameter CLK_FREQ_HZ = 85_000_000, // Frecuencia del sistema: la salida del clk_wiz_0 (gen_clk_wiz.tcl)
    parameter N_TICK    = 16, // Numero de tick necesario para muestrear un bit
    parameter NBIT      = 8,
    parameter BAUD = 19200
  )(
    input wire clock, // 100 MHz de la placa (W5)
    input wire i_reset, // BTNC, activo en alto
    input wire rx, // Linea de RX de la placa
    output wire tx, // Linea de TX de la placa
    output wire [3:0] o_led // Led: LED0 READY, LED1 RUN/STEPPING, LED2 HALTED, LED3 error de paridad
  );

  // Redondeo entero de CLK / (N_TICK*BAUD): se suma la mitad del divisor antes de dividir.
  // 85e6 / (16*19200) = 276.69 -> 277 -> 19178.7 bps -> error 0.11% < 2% (ADR-002, AC2)
  // (a 100 MHz: 325.52 -> 326 -> 19171.8 bps -> error 0.15%)
  localparam COUNT_MAX = (CLK_FREQ_HZ+(N_TICK/2)*BAUD)/(N_TICK*BAUD); // Cantidad de ciclos de clock para producir un tick del baudrate
  localparam MEM_DEPTH = 256;              // palabras de IMEM y de DMEM (ADR-008)
  localparam ADDR_BITS = $clog2(MEM_DEPTH);

  // --- Reloj ----------------------------------------------------------------------------------
  wire w_clk;     // reloj de todo el sistema
  wire w_locked;  // 1 = la salida del MMCM es estable
`ifdef SYNTHESIS
`ifndef SIN_MMCM
  `define TOP_CON_MMCM
`endif
`endif
`ifdef TOP_CON_MMCM
  clk_wiz_0 u_clk (
    .clk_in1(clock),
    .clk_out1(w_clk),
    .locked(w_locked)
  );
`else
  assign w_clk = clock;
  assign w_locked = 1'b1;
`endif

  // --- Reset ----------------------------------------------------------------------------------
  // El boton es asincrono al reloj: se sincroniza con 2 flip-flops antes de llegar a los ~2000
  // registros que resetea. Sin esto, soltar el boton cerca del flanco puede dejar a unos
  // registros en reset y a otros no en el mismo ciclo. Mantener el boton 2 ciclos mas no
  // importa (un humano lo aprieta durante millones).
  (* ASYNC_REG = "TRUE" *) reg r_rst_meta = 1'b1;
  (* ASYNC_REG = "TRUE" *) reg r_rst_sync = 1'b1;
  // Mientras el MMCM no engancho (locked = 0) el sistema queda en reset (ADR-016).
  always @(posedge w_clk)
  begin
    r_rst_meta <= i_reset || !w_locked;
    r_rst_sync <= r_rst_meta;
  end
  wire w_reset = r_rst_sync;

  // --- UART -----------------------------------------------------------------------------------
  wire w_s_tick; // Salida del Baudrate (un tick cada COUNT_MAX)
  wire w_rx_done; // Señal que indica que se recibio un Dato
  wire [NBIT-1:0] w_rx_dout; // Se almacena el dato que se recibio
  wire w_parity_err; // Se almacena la señal de error de paridad
  wire w_tx_start; // Debug Unit -> uart_tx: mandar w_tx_data
  wire [NBIT-1:0] w_tx_data;
  wire w_tx_done; // uart_tx -> Debug Unit: termino el byte

  // Sincronizador de 2 flip-flops para rx: la linea viene de la PC y es
  // asincrona al clock de la FPGA. Arranca en 1 porque la linea en reposo es alta.
  (* ASYNC_REG = "TRUE" *) reg r_rx_meta;
  (* ASYNC_REG = "TRUE" *) reg r_rx_sync;

  // Bloque de sincronizacion para metaestabilidad
  always @(posedge w_clk)
  begin
    if (w_reset)
    begin
      r_rx_meta <= 1'b1;
      r_rx_sync <= 1'b1;
    end
    else
    begin
      r_rx_meta <= rx;
      r_rx_sync <= r_rx_meta;
    end
  end

  // Modulo de Baudrate
  baudrate_gen #(
                 .COUNT_MAX(COUNT_MAX)
               ) u_baud (
                 .clock(w_clk),
                 .i_reset(w_reset),
                 .o_baudrate(w_s_tick)
               );

  // Modulo de UART rx
  uart_rx #(
            .NBIT(NBIT),
            .N_TICK(N_TICK)
          ) u_rx (
            .clock(w_clk),
            .i_reset(w_reset),
            .rx(r_rx_sync),
            .i_s_tick(w_s_tick),
            .o_rx_done(w_rx_done),
            .o_parity_err(w_parity_err),
            .o_dout(w_rx_dout)
          );

  // Modulo de UART tx
  uart_tx #(
            .NBIT(NBIT),
            .N_TICK(N_TICK)
          ) u_tx (
            .clock(w_clk),
            .i_reset(w_reset),
            .i_s_tick(w_s_tick),
            .i_tx_start(w_tx_start),
            .i_din(w_tx_data),
            .o_tx(tx),
            .o_tx_done(w_tx_done)
          );

  // --- Debug Unit <-> nucleo ------------------------------------------------------------------
  wire                 w_imem_we, w_dmem_we, w_clear_used, w_flush_all;
  wire [ADDR_BITS-1:0] w_imem_addr, w_dmem_addr;
  wire [31:0]          w_imem_wdata;
  wire                 w_enable, w_stop_fetch, w_halted, w_illegal;
  wire [31:0]          w_pc, w_reg_data, w_mem_data;
  wire [4:0]           w_reg_addr;
  wire [ADDR_BITS-1:0] w_mem_addr;
  wire                 w_mem_used;
  wire [ADDR_BITS:0]   w_used_count;
  wire                 w_stall, w_fl_ifid, w_fl_idex;
  wire [1:0]           w_fwd_a, w_fwd_b;
  wire [103:0]         w_if_id;
  wire [247:0]         w_id_ex;
  wire [151:0]         w_ex_mem;
  wire [143:0]         w_mem_wb;
  wire [3:0]           w_estado;

  debug_unit #(
               .CLK_FREQ_HZ(CLK_FREQ_HZ),
               .IMEM_ADDR_BITS(ADDR_BITS),
               .DMEM_ADDR_BITS(ADDR_BITS)
             ) u_du (
               .clock(w_clk), .i_reset(w_reset),
               .i_rx_done(w_rx_done), .i_rx_data(w_rx_dout), .i_parity_err(w_parity_err),
               .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done),
               .o_imem_we(w_imem_we), .o_imem_addr(w_imem_addr), .o_imem_wdata(w_imem_wdata),
               .o_dmem_we(w_dmem_we), .o_dmem_addr(w_dmem_addr),
               .o_clear_used(w_clear_used), .o_flush_all(w_flush_all),
               .o_enable(w_enable), .o_stop_fetch(w_stop_fetch),
               .i_halted(w_halted), .i_illegal(w_illegal),
               .i_pc(w_pc), .o_dbg_reg_addr(w_reg_addr), .i_dbg_reg_data(w_reg_data),
               .o_dbg_mem_addr(w_mem_addr), .i_dbg_mem_data(w_mem_data), .i_dbg_mem_used(w_mem_used),
               .i_dbg_used_count(w_used_count),
               .i_stall(w_stall), .i_flush_if_id(w_fl_ifid), .i_flush_id_ex(w_fl_idex),
               .i_fwd_a(w_fwd_a), .i_fwd_b(w_fwd_b),
               .i_if_id(w_if_id), .i_id_ex(w_id_ex), .i_ex_mem(w_ex_mem), .i_mem_wb(w_mem_wb),
               .o_estado(w_estado)
             );

  riscv_core #(
               .IMEM_DEPTH(MEM_DEPTH),
               .DMEM_DEPTH(MEM_DEPTH)
             ) u_core (
               .clock(w_clk), .i_reset(w_reset), .i_enable(w_enable),
               .i_flush_all(w_flush_all), .i_stop_fetch(w_stop_fetch),
               .o_halted(w_halted), .o_illegal(w_illegal), .o_pc(w_pc),
               .i_imem_we(w_imem_we), .i_imem_addr(w_imem_addr), .i_imem_wdata(w_imem_wdata),
               .i_dbg_dmem_we(w_dmem_we), .i_dbg_dmem_addr(w_dmem_addr), .i_clear_used(w_clear_used),
               .i_dbg_reg_addr(w_reg_addr), .o_dbg_reg_data(w_reg_data),
               .i_dbg_mem_addr(w_mem_addr), .o_dbg_mem_data(w_mem_data), .o_dbg_mem_used(w_mem_used),
               .o_dbg_used_count(w_used_count),
               .o_stall(w_stall), .o_flush_if_id(w_fl_ifid), .o_flush_id_ex(w_fl_idex),
               .o_fwd_a(w_fwd_a), .o_fwd_b(w_fwd_b),
               .o_if_id(w_if_id), .o_id_ex(w_id_ex), .o_ex_mem(w_ex_mem), .o_mem_wb(w_mem_wb)
             );

  // --- LEDs -----------------------------------------------------------------------------------
  reg r_led_parity;               // 1 = hubo al menos un error de paridad desde el reset

  always @(posedge w_clk)
  begin
    if (w_reset)
      r_led_parity <= 1'b0;       // se apaga solo con el boton de reset
    else if (w_parity_err)
      r_led_parity <= 1'b1;       // se prende con el primer error y queda asi
  end

  // Registrados: asi el camino al pin no arrastra la logica de la FSM (y no parpadean glitches)
  reg [2:0] r_led_estado;
  always @(posedge w_clk)
    r_led_estado <= {w_estado == `DU_ESTADO_HALTED,
                     w_estado == `DU_ESTADO_RUN || w_estado == `DU_ESTADO_STEPPING,
                     w_estado == `DU_ESTADO_READY};

  assign o_led = {r_led_parity, r_led_estado};

endmodule
