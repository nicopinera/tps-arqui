`timescale 1ns / 1ps

// Prueba del top con el eco temporal (US-401): la PC simulada (uart_host_model.vh) manda
// tramas 8E1 por `rx` a 19200 bps reales (COUNT_MAX = 326) y verifica que vuelvan iguales
// por `tx`. Una trama con paridad erronea no tiene eco y prende LED3 hasta el reset.
module tb_top_echo;
  `include "tb_utils.vh"

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  wire [3:0] w_led;
  reg  [7:0] r_eco;
  reg        r_eco_ok;

  top dut (
    .clock(clock), .i_reset(i_reset), .rx(host_tx), .tx(host_rx), .o_led(w_led)
  );

  always #5 clock = ~clock;  // 100 MHz

  // Manda un byte y verifica que vuelva igual, con paridad y stop correctos.
  task verificar_eco;
    input [7:0] dato;
    begin
      fork
        send_byte(dato);
        recv_byte(r_eco, r_eco_ok);
      join
      check_eq("eco recibido", {31'd0, r_eco_ok}, 32'd1);
      check_eq("dato del eco", {24'd0, r_eco}, {24'd0, dato});
    end
  endtask

  initial
  begin
    tb_init;
    host_ciclos_bit = dut.N_TICK * dut.COUNT_MAX;  // del top: no se repite la formula
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
      send_byte_paridad(8'h5A, ~^8'h5A);
      recv_byte(r_eco, r_eco_ok);
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
