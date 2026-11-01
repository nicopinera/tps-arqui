`timescale 1ns / 1ps

// Prueba del top con el eco temporal (US-401): la PC simulada manda tramas 8E1 por `rx`
// a 19200 bps reales (COUNT_MAX = 326) y verifica que vuelvan iguales por `tx`.
// Una trama con paridad erronea no tiene eco y prende LED3 hasta el reset.
module tb_top_echo;
  `include "tb_utils.vh"

  localparam NBIT       = 8;
  localparam MAX_CICLOS = 200000; // mas de una trama completa (11 bits x 5216 ciclos)

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  reg  r_rx = 1'b1;
  wire w_tx;
  wire [3:0] w_led;

  integer ciclos_bit;   // se toma del top para no repetir la formula de COUNT_MAX
  integer ciclos;
  reg [NBIT-1:0] r_eco;
  reg            r_eco_ok;

  top dut (
    .clock(clock), .i_reset(i_reset), .rx(r_rx), .tx(w_tx), .o_led(w_led)
  );

  always #5 clock = ~clock;  // 100 MHz

  // Lado PC -> placa: arma la trama bit por bit con el bit de paridad que se le pase.
  task enviar_trama;
    input [NBIT-1:0] dato;
    input paridad;
    integer i;
    begin
      r_rx = 1'b0;                              // start
      repeat (ciclos_bit) @(negedge clock);
      for (i = 0; i < NBIT; i = i + 1)
      begin
        r_rx = dato[i];                         // datos, LSB primero
        repeat (ciclos_bit) @(negedge clock);
      end
      r_rx = paridad;
      repeat (ciclos_bit) @(negedge clock);
      r_rx = 1'b1;                              // stop
      repeat (ciclos_bit) @(negedge clock);
    end
  endtask

  // Lado placa -> PC: espera un start en `tx` y muestrea cada bit en su centro.
  // r_eco_ok = 0 si no llego nada, o si la paridad o el stop vinieron mal.
  task recibir_trama;
    integer i;
    reg paridad;
    begin
      r_eco_ok = 1'b0;
      ciclos = 0;
      while (w_tx && ciclos < MAX_CICLOS)
      begin
        @(negedge clock);
        ciclos = ciclos + 1;
      end
      if (!w_tx)
      begin
        repeat (ciclos_bit + ciclos_bit / 2) @(negedge clock);  // centro de d0
        for (i = 0; i < NBIT; i = i + 1)
        begin
          r_eco[i] = w_tx;
          repeat (ciclos_bit) @(negedge clock);
        end
        paridad = w_tx;
        repeat (ciclos_bit) @(negedge clock);
        r_eco_ok = (paridad == ^r_eco) && w_tx;                 // paridad par y stop = 1
      end
    end
  endtask

  // Manda un byte y verifica que vuelva igual, con paridad y stop correctos.
  task verificar_eco;
    input [NBIT-1:0] dato;
    begin
      fork
        enviar_trama(dato, ^dato);
        recibir_trama;
      join
      check_eq("eco recibido", {31'd0, r_eco_ok}, 32'd1);
      check_eq("dato del eco", {24'd0, r_eco}, {24'd0, dato});
    end
  endtask

  initial
  begin
    tb_init;
    ciclos_bit = dut.N_TICK * dut.COUNT_MAX;
    check_eq("COUNT_MAX del top", dut.COUNT_MAX, 326);

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);
    check_eq("LEDs tras el reset", {28'd0, w_led}, 32'd0);

    verificar_eco(8'hA5);
    verificar_eco(8'h00);
    verificar_eco(8'hFF);

    // Paridad invertida: no hay eco y LED3 queda prendido (AC4 a nivel de top)
    fork
      enviar_trama(8'h5A, ~^8'h5A);
      recibir_trama;
    join
    check_eq("sin eco con paridad mala", {31'd0, r_eco_ok}, 32'd0);
    check_eq("LED3 tras error de paridad", {28'd0, w_led}, 32'b1000);

    // El receptor sigue andando y el LED no se apaga solo
    verificar_eco(8'h3C);
    check_eq("LED3 sigue prendido", {28'd0, w_led}, 32'b1000);

    i_reset = 1'b1;
    @(negedge clock);
    i_reset = 1'b0;
    check_eq("LED3 se apaga con reset", {28'd0, w_led}, 32'd0);

    tb_finish;
  end
endmodule
