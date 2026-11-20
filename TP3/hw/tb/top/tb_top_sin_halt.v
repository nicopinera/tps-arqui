`timescale 1ns / 1ps

// "Que sucede si en mi memoria no se encuentra una instruccion de parada?" (US-407 AC1 y AC3),
// con el sistema completo: la PC simulada habla por la UART con el top y el nucleo es el real.
//
// El du_loader se instancia SIN relleno con HALT (defparam RELLENO_HALT = 0): asi se ve lo que
// pasaria si ADR-009/010 no rellenaran la IMEM. Los tres casos imprimen una linea
// "EXPERIMENTO ..." con lo que se ve en el snapshot, para el informe.
//
//   A. IMEM en cero (como sale del bitstream) + un programa sin HALT: despues del programa el
//      nucleo busca 0x00000000, que no es una instruccion valida (ADR-018) -> termina ILLEGAL.
//   B. Primero se carga un programa largo y despues uno corto sin HALT: el corto pisa solo sus
//      palabras, y el nucleo sigue de largo y RE-EJECUTA el final del programa anterior, hasta
//      su HALT. El resultado depende de lo que se haya cargado antes.
//   C. Un lazo infinito en RUN solo termina con ABORT: snapshot con motivo ABORTED y el pipeline
//      vacio (AC1 con el nucleo real; el relleno no influye).
module tb_top_sin_halt;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam SN_ESTADO = 0, SN_PC = 5, SN_REGS = 10, SN_LATCHES = 138;
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
  defparam dut.u_du.u_loader.RELLENO_HALT = 0;

  always #5 clock = ~clock;  // 100 MHz

  // Programas (rvasm): el corto NO tiene HALT
  reg [31:0] largo [0:5];  // addi x1..x5, 1..5 / halt
  reg [31:0] corto [0:1];  // addi x10, x0, 10 / addi x11, x0, 11
  reg [31:0] lazo  [0:3];  // asm/special/infinite_loop.asm
  integer k;
  reg ok;

  function [31:0] palabra;   // 4 bytes little-endian desde host_payload[i]
    input integer i;
    palabra = {host_payload[i+3], host_payload[i+2], host_payload[i+1], host_payload[i]};
  endfunction

  function [31:0] reg_x;
    input integer n;
    reg_x = palabra(SN_REGS + 4 * n);
  endfunction

  function [3:0] valids;
    input integer dummy;
    valids = {host_payload[V_MEMWB][104%8], host_payload[V_EXMEM][112%8],
              host_payload[V_IDEX][200%8], host_payload[V_IFID][96%8]};
  endfunction

  task esperar_trama;
    input [7:0] tipo;
    input [255:0] que;
    begin
      @(negedge host_rx);   // la respuesta llega despues de todo el comando: sin timeout
      recv_frame(ok);
      check_eq(que, {31'd0, ok}, 32'd1);
      check_eq("tipo de trama", {24'd0, host_tipo}, {24'd0, tipo});
    end
  endtask

  // LOAD de las n primeras palabras de host_args[2..] (ya cargadas), con N y checksum
  task load;
    input integer n;
    integer i, x;
    begin
      host_args[0] = n[7:0];
      host_args[1] = n[15:8];
      x = 0;
      for (i = 0; i < 2 + 4 * n; i = i + 1) x = x ^ host_args[i];
      host_args[2 + 4 * n] = x[7:0];
      fork
        send_cmd(`DU_CMD_LOAD, 2 + 4 * n + 1);
        esperar_trama(`DU_TIPO_ACK, "LOAD responde ACK");
      join
    end
  endtask

  task poner;   // palabra i del programa en los argumentos del LOAD
    input integer i;
    input [31:0] w;
    {host_args[2+4*i+3], host_args[2+4*i+2], host_args[2+4*i+1], host_args[2+4*i]} = w;
  endtask

  task run_hasta_snapshot;
    begin
      fork
        send_cmd(`DU_CMD_RUN, 0);
        esperar_trama(`DU_TIPO_ACK, "RUN responde ACK");
      join
      esperar_trama(`DU_TIPO_SNAPSHOT, "llega el SNAPSHOT");
    end
  endtask

  initial
  begin
    tb_init;
    host_ciclos_bit = dut.N_TICK * dut.COUNT_MAX;
    largo[0] = 32'h0010_0093; largo[1] = 32'h0020_0113; largo[2] = 32'h0030_0193;
    largo[3] = 32'h0040_0213; largo[4] = 32'h0050_0293; largo[5] = `DU_HALT_WORD;
    corto[0] = 32'h00a0_0513; corto[1] = 32'h00b0_0593;
    lazo[0] = 32'h0000_0093; lazo[1] = 32'h0010_8093; lazo[2] = 32'hffdf_f06f;
    lazo[3] = `DU_HALT_WORD;
    // La LUTRAM de la IMEM arranca en 0 en la placa (el bitstream la inicializa asi)
    for (k = 0; k < 256; k = k + 1) dut.u_core.u_if_stage.u_instr_mem.r_mem[k] = 32'h0;

    repeat (5) @(negedge clock);
    i_reset = 1'b0;
    repeat (5) @(negedge clock);

    // ---- A. IMEM en cero despues de un programa sin HALT ----
    for (k = 0; k < 2; k = k + 1) poner(k, corto[k]);
    load(2);
    run_hasta_snapshot;
    $display("EXPERIMENTO A (IMEM en 0, sin HALT): motivo %0d (2 = ILLEGAL), PC 0x%08h, x10 = %0d, x11 = %0d",
             host_payload[SN_ESTADO][7:4], palabra(SN_PC), reg_x(10), reg_x(11));
    check_eq("A: motivo ILLEGAL", {28'd0, host_payload[SN_ESTADO][7:4]}, `DU_MOTIVO_ILLEGAL);
    check_eq("A: PC = la palabra 0 + 4", palabra(SN_PC), 32'h0000_000C);
    check_eq("A: x10", reg_x(10), 32'd10);
    check_eq("A: x11", reg_x(11), 32'd11);
    check_eq("A: pipeline vacio", {28'd0, valids(0)}, 32'd0);

    // ---- B. Programa largo y despues uno corto sin HALT, sin relleno ----
    for (k = 0; k < 6; k = k + 1) poner(k, largo[k]);
    load(6);
    for (k = 0; k < 2; k = k + 1) poner(k, corto[k]);
    load(2);
    run_hasta_snapshot;
    $display("EXPERIMENTO B (restos del programa anterior): motivo %0d (1 = HALTED), PC 0x%08h, x1..x5 = %0d %0d %0d %0d %0d, x10 = %0d, x11 = %0d",
             host_payload[SN_ESTADO][7:4], palabra(SN_PC), reg_x(1), reg_x(2), reg_x(3), reg_x(4),
             reg_x(5), reg_x(10), reg_x(11));
    check_eq("B: motivo HALTED (el del programa viejo)", {28'd0, host_payload[SN_ESTADO][7:4]}, `DU_MOTIVO_HALTED);
    check_eq("B: PC = el HALT viejo + 4", palabra(SN_PC), 32'h0000_0018);
    check_eq("B: x1 (pisado por el corto)", reg_x(1), 32'd0);
    check_eq("B: x2 (pisado por el corto)", reg_x(2), 32'd0);
    check_eq("B: x3 (re-ejecutado)", reg_x(3), 32'd3);
    check_eq("B: x4 (re-ejecutado)", reg_x(4), 32'd4);
    check_eq("B: x5 (re-ejecutado)", reg_x(5), 32'd5);
    check_eq("B: x10", reg_x(10), 32'd10);
    check_eq("B: x11", reg_x(11), 32'd11);

    // ---- C. Lazo infinito: solo lo corta ABORT ----
    for (k = 0; k < 4; k = k + 1) poner(k, lazo[k]);
    load(4);
    fork
      send_cmd(`DU_CMD_RUN, 0);
      esperar_trama(`DU_TIPO_ACK, "RUN responde ACK");
    join
    repeat (5000) @(negedge clock);
    check_eq("C: sigue en RUN", {28'd0, dut.w_estado}, `DU_ESTADO_RUN);
    fork
      send_cmd(`DU_CMD_ABORT, 0);
      esperar_trama(`DU_TIPO_SNAPSHOT, "ABORT responde SNAPSHOT");
    join
    $display("EXPERIMENTO C (lazo infinito + ABORT): motivo %0d (3 = ABORTED), vueltas x1 = %0d, valid = %b",
             host_payload[SN_ESTADO][7:4], reg_x(1), valids(0));
    check_eq("C: motivo ABORTED", {28'd0, host_payload[SN_ESTADO][7:4]}, `DU_MOTIVO_ABORTED);
    check_eq("C: el lazo dio vueltas", {31'd0, reg_x(1) > 32'd100}, 32'd1);
    check_eq("C: pipeline vacio", {28'd0, valids(0)}, 32'd0);
    check_eq("C: PC dentro del lazo", {31'd0, palabra(SN_PC) <= 32'h0000_000C}, 32'd1);

    tb_finish;
  end

  initial
  begin
    #400_000_000;
    tb_timeout("el sistema no termino");
  end
endmodule
