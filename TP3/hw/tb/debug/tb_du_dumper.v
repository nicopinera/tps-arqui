`timescale 1ns / 1ps

// Prueba de du_dumper (US-405) con du_tx_mux (canal 1) y uart_tx reales. El nucleo es un
// modelo minimo del testbench: banco de registros y DMEM con bitmap (lecturas
// combinacionales, como en docs/interfaces/riscv_core.md 2.4) y 4 buses de latches.
//
// Se verifica la trama completa contra protocolo.md 6.2:
//   - sobre: A5, tipo SNAPSHOT, longitud 221 + 6K, checksum (recv_frame);
//   - offsets 0..9: estado copiado al pedido, ciclos y PC LE, byte de riesgos;
//   - offsets 10..137: x0..x31 LE;
//   - offsets 138..218: copia de los latches tomada al pedido (despues se cambian los buses);
//   - offsets 219..220: K copiado al pedido (despues se cambia i_dbg_used_count);
//   - offsets 221..: K entradas [dir en bytes | dato] en direccion creciente, solo las usadas;
//   - o_done de un pulso, o_tx_start de un ciclo, nada sale sin pedido.
// En P7 se agrega la prueba con core_stub (AC2, AC4, AC5).
module tb_du_dumper;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam COUNT_MAX = 4;  // baud rapido: 64 ciclos por bit

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  // --- Entradas del dumper que maneja el testbench -------------------------------------
  reg        r_req = 1'b0;
  reg  [8:0] r_used_count = 9'd0;  // K que ve el dumper
  reg  [7:0] r_estado = 8'h00;     // i_snap_estado
  reg [31:0] r_ciclos = 32'd0;     // i_ciclos
  reg [31:0] r_pc = 32'd0;         // i_pc
  reg        r_stall = 1'b0, r_fl_ifid = 1'b0, r_fl_idex = 1'b0;
  reg  [1:0] r_fwd_a = 2'b00, r_fwd_b = 2'b00;
  reg  [103:0] r_if_id  = 104'd0;
  reg  [247:0] r_id_ex  = 248'd0;
  reg  [151:0] r_ex_mem = 152'd0;
  reg  [143:0] r_mem_wb = 144'd0;

  // --- Nucleo de mentira: banco de registros y DMEM con bitmap ---------------------------
  reg [31:0] tb_regs [0:31];
  reg [31:0] tb_mem  [0:255];
  reg        tb_used [0:255];
  wire [4:0]  w_reg_addr;
  wire [7:0]  w_mem_addr;
  wire [31:0] w_reg_data = tb_regs[w_reg_addr];
  wire [31:0] w_mem_data = tb_mem[w_mem_addr];
  wire        w_mem_used = tb_used[w_mem_addr];

  wire       w_done;
  wire [7:0] w_err;
  wire       w_start_1, w_done_1, w_tx_start, w_tx_done, w_s_tick;
  wire [7:0] w_data_1, w_tx_data;

  // verilator lint_off PINCONNECTEMPTY
  du_dumper u_dump (
    .clock(clock), .i_reset(i_reset),
    .i_req_dump(r_req), .i_snap_estado(r_estado), .o_done(w_done), .o_err(w_err),
    .i_ciclos(r_ciclos), .i_pc(r_pc),
    .o_dbg_reg_addr(w_reg_addr), .i_dbg_reg_data(w_reg_data),
    .o_dbg_mem_addr(w_mem_addr), .i_dbg_mem_data(w_mem_data), .i_dbg_mem_used(w_mem_used),
    .i_dbg_used_count(r_used_count),
    .i_stall(r_stall), .i_flush_if_id(r_fl_ifid), .i_flush_id_ex(r_fl_idex),
    .i_fwd_a(r_fwd_a), .i_fwd_b(r_fwd_b),
    .i_if_id(r_if_id), .i_id_ex(r_id_ex), .i_ex_mem(r_ex_mem), .i_mem_wb(r_mem_wb),
    .o_tx_start(w_start_1), .o_tx_data(w_data_1), .i_tx_done(w_done_1)
  );

  du_tx_mux u_mux (
    .i_sel(1'b1),
    .i_start_0(1'b0), .i_data_0(8'h00), .o_done_0(),
    .i_start_1(w_start_1), .i_data_1(w_data_1), .o_done_1(w_done_1),
    .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done)
  );
  // verilator lint_on PINCONNECTEMPTY

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(w_tx_start), .i_din(w_tx_data), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  always #5 clock = ~clock;

  // Monitores: pulsos de o_done y starts de mas de un ciclo
  integer n_done = 0;
  integer n_start_largo = 0;
  reg     r_start_ant = 1'b0;
  always @(posedge clock)
  begin
    if (w_done)
      n_done = n_done + 1;
    if (w_start_1 && r_start_ant)
      n_start_largo = n_start_largo + 1;
    r_start_ant = w_start_1;
  end

  // --- Preparar el "nucleo" ---------------------------------------------------------------
  // Registros con los 4 bytes distintos entre si y distintos de un registro a otro
  task llenar_regs;
    input [7:0] semilla;
    integer i;
    begin
      for (i = 0; i < 32; i = i + 1)
        tb_regs[i] = {semilla, i[7:0] ^ 8'hA0, 8'h5A, i[7:0]};
      tb_regs[0] = 32'd0;  // x0 siempre 0
    end
  endtask

  // Latches: el byte k de la copia {MEM/WB, EX/MEM, ID/EX, IF/ID} vale k ^ semilla
  task llenar_latches;
    input [7:0] semilla;
    reg [647:0] todo;
    integer k;
    begin
      for (k = 0; k < 81; k = k + 1)
        todo[8*k +: 8] = k[7:0] ^ semilla;
      {r_mem_wb, r_ex_mem, r_id_ex, r_if_id} = todo;
    end
  endtask

  // DMEM: dato = {semilla, ~dir, dir, 8'h77}; modo 0 = nada usado, 1 = solo 0, 7 y 255,
  // 2 = todo usado. Devuelve K en r_used_count.
  task llenar_mem;
    input [7:0] semilla;
    input integer modo;
    integer a;
    begin
      r_used_count = 9'd0;
      for (a = 0; a < 256; a = a + 1)
      begin
        tb_mem[a]  = {semilla, ~a[7:0], a[7:0], 8'h77};
        tb_used[a] = (modo == 2) || (modo == 1 && (a == 0 || a == 7 || a == 255));
        if (tb_used[a])
          r_used_count = r_used_count + 9'd1;
      end
    end
  endtask

  // --- Pedido y verificacion --------------------------------------------------------------
  // Pulso de i_req_dump. Despues cambian lo que el dumper tiene que haber copiado (K, estado
  // y latches): si no lo copio, se nota en la trama.
  reg [647:0] r_latches_pedido;
  reg [8:0]   r_k_pedido;
  task pedir;
    input [7:0] estado;
    begin
      @(negedge clock);
      r_estado         = estado;
      r_latches_pedido = {r_mem_wb, r_ex_mem, r_id_ex, r_if_id};
      r_k_pedido       = r_used_count;
      r_req            = 1'b1;
      @(negedge clock);
      r_req        = 1'b0;
      r_used_count = 9'd77;
      r_estado     = 8'hEE;
      llenar_latches(8'hFF);
    end
  endtask

  // Palabra LE de 4 bytes del payload recibido, desde el offset off
  function [31:0] palabra_payload;
    input integer off;
    palabra_payload = {host_payload[off+3], host_payload[off+2],
                       host_payload[off+1], host_payload[off]};
  endfunction

  // Pide un volcado y verifica la trama completa
  task verificar;
    input [7:0] estado;
    reg   [15:0] len;
    reg          ok;
    integer      done_antes, i, a, j, n_mal;
    begin
      done_antes = n_done;
      fork
        pedir(estado);
        recv_frame(ok);
      join
      repeat (4 * host_ciclos_bit) @(negedge clock);  // el o_done llega tras el STOP
      len = 16'd221 + 16'd6 * {7'd0, r_k_pedido};

      // Sobre
      check_eq("trama valida (A5 y checksum)", {31'd0, ok}, 32'd1);
      check_eq("tipo SNAPSHOT", {24'd0, host_tipo}, {24'd0, `DU_TIPO_SNAPSHOT});
      check_eq("longitud 221 + 6K", {16'd0, host_len}, {16'd0, len});

      // Cabecera (offsets 0..9)
      check_eq("off 0: estado del pedido", {24'd0, host_payload[0]}, {24'd0, estado});
      check_eq("off 1: ciclos LE", palabra_payload(1), r_ciclos);
      check_eq("off 5: PC LE", palabra_payload(5), r_pc);
      check_eq("off 9: riesgos",
               {24'd0, host_payload[9]},
               {24'd0, 1'b0, r_fwd_b, r_fwd_a, r_fl_idex, r_fl_ifid, r_stall});

      // Registros (offsets 10..137)
      n_mal = 0;
      for (i = 0; i < 32; i = i + 1)
        if (palabra_payload(10 + 4 * i) !== tb_regs[i])
        begin
          if (n_mal == 0)
            $display("  x%0d: llego 0x%08h, esperado 0x%08h", i, palabra_payload(10 + 4 * i), tb_regs[i]);
          n_mal = n_mal + 1;
        end
      check_eq("off 10: x0..x31 LE", n_mal, 0);

      // Latches (offsets 138..218): la copia del pedido, no lo que hay ahora en los buses
      n_mal = 0;
      for (i = 0; i < 81; i = i + 1)
        if (host_payload[138 + i] !== r_latches_pedido[8*i +: 8])
        begin
          if (n_mal == 0)
            $display("  latch byte %0d: llego 0x%02h, esperado 0x%02h", i, host_payload[138 + i], r_latches_pedido[8*i +: 8]);
          n_mal = n_mal + 1;
        end
      check_eq("off 138: latches del pedido", n_mal, 0);

      // K (offsets 219..220)
      check_eq("off 219: K LE", {16'd0, host_payload[220], host_payload[219]}, {23'd0, r_k_pedido});

      // Memoria (offsets 221..): las usadas, en orden creciente
      n_mal = 0;
      j = 0;
      for (a = 0; a < 256; a = a + 1)
        if (tb_used[a])
        begin
          if ({host_payload[222 + 6*j], host_payload[221 + 6*j]} !== a * 4 ||
              palabra_payload(223 + 6*j) !== tb_mem[a])
          begin
            if (n_mal == 0)
              $display("  entrada %0d (dir 0x%03h): llego dir 0x%02h%02h dato 0x%08h", j, a * 4,
                       host_payload[222 + 6*j], host_payload[221 + 6*j], palabra_payload(223 + 6*j));
            n_mal = n_mal + 1;
          end
          j = j + 1;
        end
      check_eq("off 221: memoria usada", n_mal, 0);

      check_eq("o_done: un solo pulso", n_done - done_antes, 1);
      check_eq("o_err en 0", {24'd0, w_err}, 32'd0);
    end
  endtask

  reg [7:0] r_b;
  reg       r_ok;

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    // 1) Programa que no escribio memoria (AC3): K = 0, longitud 221
    r_ciclos = 32'h1122_3344;
    r_pc     = 32'h0000_0014;
    llenar_regs(8'h10);
    llenar_latches(8'h00);
    llenar_mem(8'hC0, 0);
    verificar(8'h04);    // STEPPING sin motivo

    // 2) Palabras usadas en los bordes de la DMEM (0, 7 y 255): K = 3. Riesgos con cada
    //    bit distinto del volcado anterior.
    r_ciclos = 32'hA1B2_C3D4;
    r_pc     = 32'h0000_03FC;
    r_stall  = 1'b1;  r_fl_ifid = 1'b0;  r_fl_idex = 1'b1;
    r_fwd_a  = 2'b10; r_fwd_b   = 2'b01;
    llenar_regs(8'h20);
    llenar_latches(8'h3C);
    llenar_mem(8'hC1, 1);
    verificar(8'h16);    // motivo HALTED, estado HALTED

    // 3) DMEM llena: K = 256, longitud 1757 (la trama mas larga)
    r_stall  = 1'b0;  r_fl_ifid = 1'b1;  r_fl_idex = 1'b0;
    r_fwd_a  = 2'b01; r_fwd_b   = 2'b10;
    llenar_regs(8'h30);
    llenar_latches(8'h81);
    llenar_mem(8'hC2, 2);
    verificar(8'h26);    // motivo ILLEGAL, estado HALTED

    check_eq("o_tx_start nunca dura 2 ciclos", n_start_largo, 0);

    // Sin pedido no sale nada
    recv_byte(r_b, r_ok);
    check_eq("sin pedido no sale nada", {31'd0, r_ok}, 32'd0);

    tb_finish;
  end
endmodule
