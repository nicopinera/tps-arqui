`timescale 1ns / 1ps

// Prueba de du_loader (US-404) con core_stub (US-402): el testbench hace de du_cmd_fsm
// (pulsos i_req_load / i_load_byte / i_load_cancel / i_req_reset) y mira lo que quedo
// escrito en la IMEM y la DMEM del nucleo falso y los pulsos que salieron.
//
//   carga valida       IMEM = programa en [0, N-1] y HALT en [N, 255]; DMEM en 0; bitmap
//                      y contador en 0; PC = 0; un o_done con err = 0 y un flush/load_done
//   N = 256            no queda ningun HALT (borde de r_inicio)
//   AC3/AC7 checksum   NACK(ERR_CHECKSUM) y toda la IMEM en HALT
//   AC7 cancelacion    sin o_done, toda la IMEM en HALT (tambien cancelando en LIMPIAR)
//   ERR_TAMANO         N = 0 y N > 256: toda la IMEM en HALT; los bytes que siguen llegando
//                      se ignoran
//   AC4 RESET          la IMEM no cambia, la DMEM queda en 0, sale o_reset_done y no o_done
//   AC5                cinco cargas seguidas de programas distintos, sin reset en el medio
module tb_du_loader;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam DEPTH      = `DU_IMEM_DEPTH;
  localparam MAX_CICLOS = 2000;   // LIMPIAR tarda 256 + 1; esto sobra

  reg clock = 1'b0;
  reg i_reset = 1'b1;
  always #5 clock = ~clock;

  // --- Lo que manda la FSM -----------------------------------------------------------------
  reg       r_req_load = 1'b0, r_load_byte = 1'b0, r_load_cancel = 1'b0, r_req_reset = 1'b0;
  reg [7:0] r_load_data = 8'h00;
  reg       r_enable = 1'b0;      // el nucleo falso corre: ensucia DMEM, bitmap y PC

  // --- Salidas del loader ------------------------------------------------------------------
  wire       w_done, w_reset_done, w_imem_we, w_dmem_we, w_clear_used, w_flush_all, w_load_done;
  wire [7:0] w_err, w_imem_addr, w_dmem_addr;
  wire [31:0] w_imem_wdata;
  wire [31:0] w_pc;
  wire [8:0]  w_used_count;

  du_loader u_dut (
    .clock(clock), .i_reset(i_reset),
    .i_req_load(r_req_load), .i_load_byte(r_load_byte), .i_load_data(r_load_data),
    .i_load_cancel(r_load_cancel), .o_done(w_done), .o_err(w_err),
    .i_req_reset(r_req_reset), .o_reset_done(w_reset_done),
    .o_imem_we(w_imem_we), .o_imem_addr(w_imem_addr), .o_imem_wdata(w_imem_wdata),
    .o_dmem_we(w_dmem_we), .o_dmem_addr(w_dmem_addr),
    .o_clear_used(w_clear_used), .o_flush_all(w_flush_all),
    .o_load_done(w_load_done)
  );

  core_stub u_core (
    .clock(clock), .i_reset(i_reset), .i_enable(r_enable),
    .i_flush_all(w_flush_all), .i_stop_fetch(1'b0),
    .o_halted(), .o_illegal(), .o_pc(w_pc),
    .i_imem_we(w_imem_we), .i_imem_addr(w_imem_addr), .i_imem_wdata(w_imem_wdata),
    .i_dbg_dmem_we(w_dmem_we), .i_dbg_dmem_addr(w_dmem_addr), .i_clear_used(w_clear_used),
    .i_dbg_reg_addr(5'd0), .o_dbg_reg_data(),
    .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_used(),
    .o_dbg_used_count(w_used_count),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(), .o_id_ex(), .o_ex_mem(), .o_mem_wb()
  );

  // --- Contadores de pulsos ----------------------------------------------------------------
  integer n_done = 0, n_reset_done = 0, n_flush = 0, n_clear = 0, n_load_done = 0;
  reg [7:0] ultimo_err = 8'h00;

  always @(posedge clock)
  begin
    if (w_done)       begin n_done = n_done + 1; ultimo_err = w_err; end
    if (w_reset_done) n_reset_done = n_reset_done + 1;
    if (w_flush_all)  n_flush = n_flush + 1;
    if (w_clear_used) n_clear = n_clear + 1;
    if (w_load_done)  n_load_done = n_load_done + 1;
  end

  // --- Programa de prueba: palabra i del programa "semilla" --------------------------------
  // Los 4 bytes son distintos entre si, asi un error de endianness se nota.
  function [31:0] palabra;
    input [7:0] semilla;
    input integer i;
    palabra = {semilla, i[7:0] ^ 8'h3C, 8'h96, i[7:0]};
  endfunction

  // --- Estimulos (se cambian en el flanco de bajada, como si vinieran de un registro) ------
  task pulso_req_load;
    begin
      @(negedge clock) r_req_load = 1'b1;
      @(negedge clock) r_req_load = 1'b0;
    end
  endtask

  task pulso_req_reset;
    begin
      @(negedge clock) r_req_reset = 1'b1;
      @(negedge clock) r_req_reset = 1'b0;
    end
  endtask

  task pulso_cancel;
    begin
      @(negedge clock) r_load_cancel = 1'b1;
      @(negedge clock) r_load_cancel = 1'b0;
    end
  endtask

  // Un byte, con un ciclo libre despues (en la placa hay ~1000 ciclos entre bytes)
  task mandar_byte;
    input [7:0] b;
    begin
      @(negedge clock) begin r_load_byte = 1'b1; r_load_data = b; end
      @(negedge clock) r_load_byte = 1'b0;
    end
  endtask

  reg [7:0] xor_tx;   // XOR de los bytes mandados (lo que calcula la PC)

  task mandar_byte_xor;
    input [7:0] b;
    begin
      xor_tx = xor_tx ^ b;
      mandar_byte(b);
    end
  endtask

  // LOAD completo: req, N (LE), N palabras (LE) y checksum (roto si checksum_ok = 0)
  task cargar;
    input [7:0]  semilla;
    input integer n;
    input        checksum_ok;
    integer i;
    reg [31:0] w;
    begin
      xor_tx = 8'h00;
      pulso_req_load;
      mandar_byte_xor(n[7:0]);
      mandar_byte_xor(n[15:8]);
      for (i = 0; i < n; i = i + 1)
      begin
        w = palabra(semilla, i);
        mandar_byte_xor(w[7:0]);
        mandar_byte_xor(w[15:8]);
        mandar_byte_xor(w[23:16]);
        mandar_byte_xor(w[31:24]);
      end
      mandar_byte(checksum_ok ? xor_tx : ~xor_tx);
    end
  endtask

  // Espera a que un contador cambie respecto de "antes" (o corta el test)
  task esperar_done;
    input integer antes;
    integer c;
    begin
      c = 0;
      while (n_done == antes && c < MAX_CICLOS) begin @(posedge clock); c = c + 1; end
      if (c >= MAX_CICLOS) tb_timeout("no llego o_done");
      @(negedge clock);
    end
  endtask

  task esperar_reset_done;
    input integer antes;
    integer c;
    begin
      c = 0;
      while (n_reset_done == antes && c < MAX_CICLOS) begin @(posedge clock); c = c + 1; end
      if (c >= MAX_CICLOS) tb_timeout("no llego o_reset_done");
      @(negedge clock);
    end
  endtask

  task esperar_ciclos;
    input integer n;
    begin
      repeat (n) @(negedge clock);
    end
  endtask

  // El nucleo falso corre unos ciclos: escribe en la DMEM, marca el bitmap y mueve el PC
  task ensuciar_nucleo;
    begin
      @(negedge clock) r_enable = 1'b1;
      esperar_ciclos(40);
      r_enable = 1'b0;
    end
  endtask

  // --- Chequeos sobre las memorias del nucleo falso ----------------------------------------
  // Cuenta las posiciones que no coinciden y hace un solo check_eq por region.
  task check_imem;
    input [255:0] nombre;
    input [7:0]   semilla;
    input integer n;          // programa en [0, n-1], HALT en [n, DEPTH-1]
    integer i, mal_prog, mal_halt;
    begin
      mal_prog = 0;
      mal_halt = 0;
      for (i = 0; i < DEPTH; i = i + 1)
        if (i < n)
        begin
          if (u_core.r_imem[i] !== palabra(semilla, i)) mal_prog = mal_prog + 1;
        end
        else if (u_core.r_imem[i] !== `DU_HALT_WORD)
          mal_halt = mal_halt + 1;
      check_eq(nombre, mal_prog, 0);
      check_eq("  ... posiciones sin HALT", mal_halt, 0);
    end
  endtask

  task check_dmem_limpia;
    integer i, mal;
    begin
      mal = 0;
      for (i = 0; i < `DU_DMEM_DEPTH; i = i + 1)
        if (u_core.r_dmem[i] !== 32'd0) mal = mal + 1;
      check_eq("DMEM toda en 0", mal, 0);
      check_eq("contador de usadas en 0", {23'd0, w_used_count}, 0);
      check_eq("PC en 0 (flush_all)", w_pc, 0);
    end
  endtask

  // Carga valida completa con todos sus chequeos
  task carga_valida;
    input [7:0]  semilla;
    input integer n;
    integer d0, f0, c0, l0;
    begin
      ensuciar_nucleo;
      d0 = n_done; f0 = n_flush; c0 = n_clear; l0 = n_load_done;
      cargar(semilla, n, 1);
      esperar_done(d0);
      check_eq("carga valida: err = 0", ultimo_err, 8'h00);
      check_imem("carga valida: programa en IMEM", semilla, n);
      check_dmem_limpia;
      esperar_ciclos(5);   // que no salga un segundo pulso
      check_eq("un solo o_done", n_done - d0, 1);
      check_eq("un solo o_flush_all", n_flush - f0, 1);
      check_eq("un solo o_clear_used", n_clear - c0, 1);
      check_eq("un solo o_load_done", n_load_done - l0, 1);
    end
  endtask

  integer d0, r0, f0, k;

  initial
  begin
    tb_init;
    esperar_ciclos(3);
    i_reset = 1'b0;
    esperar_ciclos(2);

    // --- Carga valida chica y N = 256 ---------------------------------------------------
    $display("Carga valida (N = 5)");
    carga_valida(8'hA1, 5);

    $display("Carga valida con N = 256 (sin HALT)");
    carga_valida(8'hB2, 256);

    // --- AC3 / AC7: checksum incorrecto -------------------------------------------------
    $display("Checksum incorrecto");
    carga_valida(8'hC3, 7);              // deja un programa para ver que desaparece
    d0 = n_done;
    cargar(8'hD4, 4, 0);
    esperar_done(d0);
    check_eq("checksum malo: ERR_CHECKSUM", ultimo_err, `DU_ERR_CHECKSUM);
    check_imem("checksum malo: IMEM toda en HALT", 8'h00, 0);
    check_dmem_limpia;

    // --- AC7: cancelacion a mitad de la carga -------------------------------------------
    $display("Cancelacion a mitad de la carga");
    carga_valida(8'hE5, 9);
    ensuciar_nucleo;
    d0 = n_done; f0 = n_flush;
    pulso_req_load;
    mandar_byte(8'd10);                  // N = 10
    mandar_byte(8'd0);
    for (k = 0; k < 9; k = k + 1)        // 2 palabras y un pedazo de la tercera
      mandar_byte(8'h55);
    pulso_cancel;
    esperar_ciclos(300);
    check_eq("cancel: sin o_done", n_done - d0, 0);
    check_eq("cancel: un flush_all", n_flush - f0, 1);
    check_imem("cancel: IMEM toda en HALT", 8'h00, 0);
    check_dmem_limpia;

    $display("Cancelacion durante LIMPIAR");
    carga_valida(8'hF6, 3);
    d0 = n_done;
    cargar(8'h17, 6, 1);                 // checksum bien: arranca LIMPIAR
    esperar_ciclos(20);                  // en medio del recorrido
    pulso_cancel;
    esperar_ciclos(300);
    check_eq("cancel en LIMPIAR: sin o_done", n_done - d0, 0);
    check_imem("cancel en LIMPIAR: IMEM en HALT", 8'h00, 0);

    // --- ERR_TAMANO: N = 0 y N > 256 ----------------------------------------------------
    $display("ERR_TAMANO con N = 300");
    carga_valida(8'h28, 4);
    d0 = n_done;
    pulso_req_load;
    mandar_byte(8'h2C);                  // N = 300 = 0x012C
    mandar_byte(8'h01);
    for (k = 0; k < 12; k = k + 1)       // el resto de la carga sigue llegando
      mandar_byte(8'h77);
    esperar_done(d0);
    check_eq("N = 300: ERR_TAMANO", ultimo_err, `DU_ERR_TAMANO);
    for (k = 0; k < 12; k = k + 1)       // y sigue llegando despues del o_done
      mandar_byte(8'h77);
    esperar_ciclos(5);
    check_eq("N = 300: un solo o_done", n_done - d0, 1);
    check_imem("N = 300: IMEM toda en HALT", 8'h00, 0);

    $display("ERR_TAMANO con N = 0");
    carga_valida(8'h39, 4);
    d0 = n_done;
    pulso_req_load;
    mandar_byte(8'h00);
    mandar_byte(8'h00);
    esperar_done(d0);
    check_eq("N = 0: ERR_TAMANO", ultimo_err, `DU_ERR_TAMANO);
    check_imem("N = 0: IMEM toda en HALT", 8'h00, 0);

    // --- AC4: RESET no toca la IMEM -----------------------------------------------------
    $display("RESET");
    carga_valida(8'h4A, 11);
    ensuciar_nucleo;
    d0 = n_done; r0 = n_reset_done; f0 = n_flush;
    pulso_req_reset;
    esperar_reset_done(r0);
    esperar_ciclos(5);
    check_eq("RESET: un o_reset_done", n_reset_done - r0, 1);
    check_eq("RESET: sin o_done", n_done - d0, 0);
    check_eq("RESET: un flush_all", n_flush - f0, 1);
    check_imem("RESET: IMEM intacta", 8'h4A, 11);
    check_dmem_limpia;

    // --- AC5: cinco cargas seguidas -----------------------------------------------------
    $display("Cinco cargas seguidas");
    carga_valida(8'h51, 20);
    carga_valida(8'h62, 3);
    carga_valida(8'h73, 1);
    carga_valida(8'h84, 64);
    carga_valida(8'h95, 2);

    tb_finish;
  end

  // Guardia general: ningun test deberia tardar tanto
  initial
  begin
    #20_000_000;
    tb_timeout("simulacion colgada");
  end

endmodule
