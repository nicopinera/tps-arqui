`timescale 1ns / 1ps

// Prueba del sistema completo (US-411 AC5, version minima): la PC simulada habla con el top
// por la UART, como en la placa, y el nucleo es el real.
//
//   host model -> rx -> top (uart_rx -> debug_unit -> riscv_core, uart_tx) -> tx -> host model
//
// Secuencia: PING -> LOAD del programa -> RUN -> ACK -> SNAPSHOT final, que se compara con el
// golden model igual que tb_core_programs: motivo, PC (el de la ultima instruccion + 4),
// x1..x31 y la memoria usada. Ademas se miran los LEDs (READY despues del LOAD, HALTED al
// final) y que el pipeline quede vacio (los 4 valid del snapshot en 0).
//
// Plusargs (opcionales, los arma make sim-system):
//   +HEX=<ruta>        programa ensamblado (rvasm, una palabra por linea)
//   +EXPECTED=<ruta>   estado final del golden model (rvsim --expect)
// Sin plusargs corre el programa del ejemplo de docs/protocolo.md 8.2 y 8.7, asi sim-all
// tambien prueba el top.
//
// La UART va a 1,5625 Mbps (COUNT_MAX = 4, 64 ciclos por bit) en vez de 19200, para que la
// simulacion tarde segundos y no minutos. El top es el mismo: solo cambia el parametro BAUD.
module tb_top_system;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam MAX_PALABRAS = 256;
  localparam EXP_PC = 1, EXP_REGS = 2, EXP_K = 34, EXP_PARES = 35;
  localparam EXP_MAX = EXP_PARES + 2 * MAX_PALABRAS;
  // Offsets del payload SNAPSHOT (docs/protocolo.md 6.2)
  localparam SN_ESTADO = 0, SN_PC = 5, SN_REGS = 10, SN_LATCHES = 138, SN_K = 219,
             SN_MEM = 221;
  // Byte del payload con el valid de cada latch: bit 96 de IF/ID, 200 de ID/EX, 112 de
  // EX/MEM y 104 de MEM/WB (riscv_core.md 4), contados desde el inicio de cada latch
  localparam V_IFID = SN_LATCHES + 96 / 8, V_IDEX = SN_LATCHES + 13 + 200 / 8,
             V_EXMEM = SN_LATCHES + 13 + 31 + 112 / 8, V_MEMWB = SN_LATCHES + 13 + 31 + 19 + 104 / 8;

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  wire [3:0] w_led;

  top #(.BAUD(1_562_500)) dut (
    .clock(clock), .i_reset(i_reset), .rx(host_tx), .tx(host_rx), .o_led(w_led)
  );

  always #5 clock = ~clock;  // 100 MHz

  reg [31:0] r_programa [0:MAX_PALABRAS-1];
  reg [31:0] r_esperado [0:EXP_MAX-1];
  reg [8*256-1:0] r_hex, r_expected;
  integer n, k, xor_acum;
  reg ok;

  function [31:0] palabra_payload;   // 4 bytes little-endian desde host_payload[i]
    input integer i;
    palabra_payload = {host_payload[i+3], host_payload[i+2], host_payload[i+1], host_payload[i]};
  endfunction

  task esperar_trama;
    input [7:0] tipo;
    input [255:0] que;
    begin
      // La respuesta llega despues de todo el comando (un LOAD son cientos de bytes) o de todo
      // el programa: esperar el bit de start sin el timeout de recv_byte. Si nunca llega, corta
      // el timeout global.
      @(negedge host_rx);
      recv_frame(ok);
      check_eq(que, {31'd0, ok}, 32'd1);
      check_eq("tipo de trama", {24'd0, host_tipo}, {24'd0, tipo});
    end
  endtask

  initial
  begin
    tb_init;
    host_ciclos_bit = dut.N_TICK * dut.COUNT_MAX;

    // ---- Programa y estado esperado ----
    for (k = 0; k < MAX_PALABRAS; k = k + 1) r_programa[k] = 32'hxxxx_xxxx;
    for (k = 0; k < EXP_MAX; k = k + 1) r_esperado[k] = 32'h0;
    if ($value$plusargs("HEX=%s", r_hex) && $value$plusargs("EXPECTED=%s", r_expected))
    begin
      $readmemh(r_hex, r_programa);
      $readmemh(r_expected, r_esperado);
      $display("Programa: %0s", r_hex);
    end
    else
    begin
      // docs/protocolo.md 8.2: addi x1, x0, 5 / sw x1, 0(x0) / halt
      r_programa[0] = 32'h0050_0093;
      r_programa[1] = 32'h0010_2023;
      r_programa[2] = `DU_HALT_WORD;
      r_esperado[0] = 32'd1;                 // HALTED
      r_esperado[EXP_PC] = 32'h8;            // el HALT
      r_esperado[EXP_REGS + 1] = 32'd5;      // x1
      r_esperado[EXP_K] = 32'd1;
      r_esperado[EXP_PARES] = 32'h0;         // [0x000] = 5
      r_esperado[EXP_PARES + 1] = 32'd5;
      $display("Programa: el de docs/protocolo.md 8.2 (sin +HEX)");
    end
    n = 0;
    while (n < MAX_PALABRAS && r_programa[n] !== 32'hxxxx_xxxx) n = n + 1;

    repeat (5) @(negedge clock);
    i_reset = 1'b0;
    repeat (5) @(negedge clock);

    // ---- PING: la cadena UART -> Debug Unit -> UART anda ----
    fork
      send_cmd(`DU_CMD_PING, 0);
      esperar_trama(`DU_TIPO_PING_INFO, "PING responde");
    join

    // ---- LOAD: N (LE), N palabras (LE), XOR de todo lo anterior ----
    host_args[0] = n[7:0];
    host_args[1] = n[15:8];
    for (k = 0; k < n; k = k + 1)
      {host_args[2+4*k+3], host_args[2+4*k+2], host_args[2+4*k+1], host_args[2+4*k]} = r_programa[k];
    xor_acum = 0;
    for (k = 0; k < 2 + 4 * n; k = k + 1) xor_acum = xor_acum ^ host_args[k];
    host_args[2 + 4 * n] = xor_acum[7:0];
    fork
      send_cmd(`DU_CMD_LOAD, 2 + 4 * n + 1);
      esperar_trama(`DU_TIPO_ACK, "LOAD responde");
    join
    // La DU cambia de estado al terminar el bit de stop de su respuesta (i_resp_done), y el
    // host termina de leer a la mitad de ese bit: esperar un poco mas
    repeat (2 * host_ciclos_bit) @(negedge clock);
    check_eq("LED0 = READY tras el LOAD", {28'd0, w_led}, 32'b0001);

    // ---- RUN: ACK enseguida y SNAPSHOT al terminar ----
    fork
      send_cmd(`DU_CMD_RUN, 0);
      esperar_trama(`DU_TIPO_ACK, "RUN responde ACK");
    join
    esperar_trama(`DU_TIPO_SNAPSHOT, "llega el SNAPSHOT final");

    // ---- Comparar con el golden model ----
    check_eq("longitud = 221 + 6K", {16'd0, host_len},
             `DU_SNAPSHOT_FIJO + `DU_SNAP_PALABRA_USADA * r_esperado[EXP_K]);
    check_eq("motivo", {28'd0, host_payload[SN_ESTADO][7:4]}, r_esperado[0]);
    check_eq("estado = HALTED", {28'd0, host_payload[SN_ESTADO][3:0]}, `DU_ESTADO_HALTED);
    check_eq("PC = el del HALT + 4", palabra_payload(SN_PC), r_esperado[EXP_PC] + 32'd4);
    for (k = 1; k < 32; k = k + 1)
    begin
      if (palabra_payload(SN_REGS + 4 * k) !== r_esperado[EXP_REGS + k])
        $display("  x%0d = 0x%08h, golden model 0x%08h", k, palabra_payload(SN_REGS + 4 * k),
                 r_esperado[EXP_REGS + k]);
      check_eq("registro", palabra_payload(SN_REGS + 4 * k), r_esperado[EXP_REGS + k]);
    end
    check_eq("K", {16'd0, host_payload[SN_K+1], host_payload[SN_K]}, r_esperado[EXP_K]);
    for (k = 0; k < r_esperado[EXP_K] && k < MAX_PALABRAS; k = k + 1)
    begin
      check_eq("memoria: direccion",
               {16'd0, host_payload[SN_MEM+6*k+1], host_payload[SN_MEM+6*k]},
               r_esperado[EXP_PARES + 2 * k]);
      check_eq("memoria: dato", palabra_payload(SN_MEM + 6 * k + 2), r_esperado[EXP_PARES + 2 * k + 1]);
    end
    check_eq("pipeline vacio (4 valid)",
             {28'd0, host_payload[V_MEMWB][104%8], host_payload[V_EXMEM][112%8],
              host_payload[V_IDEX][200%8], host_payload[V_IFID][96%8]}, 32'd0);
    repeat (2 * host_ciclos_bit) @(negedge clock);
    check_eq("LED2 = HALTED al final", {28'd0, w_led}, 32'b0100);

    tb_finish;
  end

  initial
  begin
    #400_000_000;  // 40 M ciclos: un LOAD de 256 palabras + un snapshot lleno es ~2 M
    tb_timeout("el sistema no termino");
  end
endmodule
