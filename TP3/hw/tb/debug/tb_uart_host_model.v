`timescale 1ns / 1ps

// Prueba del modelo de la PC (US-402): send_byte entra a uart_rx y recv_byte recibe lo que
// manda uart_tx (AC2). Valida el modelo contra la UART que ya esta probada.
module tb_uart_host_model;
  `include "tb_utils.vh"

  localparam COUNT_MAX = 4;  // baud rapido: 64 ciclos por bit

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  reg  r_tx_start = 1'b0;
  reg  [7:0] r_tx_din = 8'h00;
  wire w_s_tick;
  wire w_rx_done;
  wire w_parity_err;
  wire w_tx_done;
  wire [7:0] w_rx_dout;

  reg  [7:0] r_dato;
  reg        r_ok;
  integer    ciclos;

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_rx u_rx (
    .clock(clock), .i_reset(i_reset), .rx(host_tx), .i_s_tick(w_s_tick),
    .o_rx_done(w_rx_done), .o_parity_err(w_parity_err), .o_dout(w_rx_dout)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(r_tx_start), .i_din(r_tx_din), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  always #5 clock = ~clock;

  // PC -> FPGA: send_byte y espera el o_rx_done de uart_rx.
  task verificar_envio;
    input [7:0] dato;
    begin
      fork
        send_byte(dato);
        begin
          ciclos = 0;
          while (!w_rx_done && ciclos < 20 * host_ciclos_bit)
          begin
            @(negedge clock);
            ciclos = ciclos + 1;
          end
          check_eq("uart_rx recibio el byte", {31'd0, w_rx_done}, 32'd1);
          check_eq("dato en uart_rx", {24'd0, w_rx_dout}, {24'd0, dato});
        end
      join
    end
  endtask

  // FPGA -> PC: uart_tx manda un byte y recv_byte lo tiene que reconstruir.
  // recv_byte vuelve en el centro del stop; se espera la bajada de o_tx_done (uart_tx ya
  // en IDLE) porque ignora i_tx_start mientras sigue en STOP.
  task verificar_recepcion;
    input [7:0] dato;
    begin
      fork
        begin
          @(negedge clock);
          r_tx_din   = dato;
          r_tx_start = 1'b1;
          @(negedge clock);
          r_tx_start = 1'b0;
          @(negedge w_tx_done);
        end
        recv_byte(r_dato, r_ok);
      join
      check_eq("recv_byte ok", {31'd0, r_ok}, 32'd1);
      check_eq("dato en recv_byte", {24'd0, r_dato}, {24'd0, dato});
    end
  endtask

  // --- AC3 y tramas: send_cmd con errores y recv_frame ---------------------------------

  // Los pulsos de uart_rx duran un ciclo: se cuentan en cada flanco para no perder ninguno.
  integer n_rx_done = 0;
  integer n_parity_err = 0;
  always @(posedge clock)
  begin
    if (w_rx_done)
      n_rx_done = n_rx_done + 1;
    if (w_parity_err)
      n_parity_err = n_parity_err + 1;
  end

  // Manda un comando y verifica cuantos bytes buenos y con paridad mala vio uart_rx.
  task verificar_cmd;
    input [7:0]   cmd;
    input integer n_args;
    input integer done_esperados;
    input integer err_esperados;
    integer done_antes, err_antes;
    begin
      done_antes = n_rx_done;
      err_antes  = n_parity_err;
      send_cmd(cmd, n_args);
      repeat (host_ciclos_bit) @(negedge clock);
      check_eq("bytes buenos en uart_rx", n_rx_done - done_antes, done_esperados);
      check_eq("bytes con paridad mala", n_parity_err - err_antes, err_esperados);
      check_eq("linea en reposo al terminar", {31'd0, host_tx}, 32'd1);
    end
  endtask

  // Lado FPGA: uart_tx manda r_trama[0..n-1] uno detras de otro, como haria la Debug Unit.
  reg [7:0] r_trama [0:7];
  task enviar_trama_por_tx;
    input integer n;
    integer i;
    begin
      for (i = 0; i < n; i = i + 1)
      begin
        @(negedge clock);
        r_tx_din   = r_trama[i];
        r_tx_start = 1'b1;
        @(negedge clock);
        r_tx_start = 1'b0;
        @(negedge w_tx_done);
      end
    end
  endtask

  // Ejemplos de docs/protocolo.md (seccion 8.1) cargados en r_trama.
  task cargar_trama;
    input [7:0] b0, b1, b2, b3, b4, b5;
    begin
      r_trama[0] = b0; r_trama[1] = b1; r_trama[2] = b2;
      r_trama[3] = b3; r_trama[4] = b4; r_trama[5] = b5;
    end
  endtask

  task verificar_frame;
    input integer n;
    input         ok_esperado;
    begin
      fork
        enviar_trama_por_tx(n);
        recv_frame(r_ok);
      join
      check_eq("recv_frame ok", {31'd0, r_ok}, {31'd0, ok_esperado});
    end
  endtask

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    verificar_envio(8'hA5);
    verificar_envio(8'h00);
    verificar_envio(8'hFF);
    verificar_envio(8'h01);

    verificar_recepcion(8'h5A);
    verificar_recepcion(8'h80);
    verificar_recepcion(8'hFF);

    // Sin nada en la linea, recv_byte tiene que cortar por timeout y no colgarse
    recv_byte(r_dato, r_ok);
    check_eq("recv_byte sin datos: timeout", {31'd0, r_ok}, 32'd0);

    // send_cmd completo: 'M' (DUMP_MEM) desde la direccion 0x0000, 4 palabras
    host_args[0] = 8'h00;
    host_args[1] = 8'h00;
    host_args[2] = 8'h04;
    host_args[3] = 8'h00;
    verificar_cmd(8'h4D, 4, 5, 0);
    // Paridad mala en un argumento (byte 2): uart_rx lo descarta y avisa (AC3)
    host_paridad_mala_en = 2;
    verificar_cmd(8'h4D, 4, 4, 1);
    // Paridad mala en el codigo de comando (byte 0)
    host_paridad_mala_en = 0;
    verificar_cmd(8'h4D, 4, 4, 1);
    host_paridad_mala_en = -1;
    // LOAD truncado: 'L' + solo el primer byte de N (faltan el resto y el checksum) (AC3)
    host_args[0] = 8'h03;
    host_args[1] = 8'h00;
    verificar_cmd(8'h4C, 1, 2, 0);

    // recv_frame con tramas de docs/protocolo.md: ACK, PING_INFO y NACK(ERR_PARIDAD)
    cargar_trama(8'hA5, 8'h01, 8'h00, 8'h00, 8'h01, 8'h00);
    verificar_frame(5, 1'b1);
    check_eq("ACK: tipo", {24'd0, host_tipo}, 32'h01);
    check_eq("ACK: longitud", {16'd0, host_len}, 32'd0);

    cargar_trama(8'hA5, 8'h04, 8'h01, 8'h00, 8'h01, 8'h04);
    verificar_frame(6, 1'b1);
    check_eq("PING_INFO: tipo", {24'd0, host_tipo}, 32'h04);
    check_eq("PING_INFO: version", {24'd0, host_payload[0]}, 32'h01);

    cargar_trama(8'hA5, 8'h02, 8'h01, 8'h00, 8'h07, 8'h04);
    verificar_frame(6, 1'b1);
    check_eq("NACK: codigo de error", {24'd0, host_payload[0]}, 32'h07);

    // Checksum corrupto (04 -> 05) y trama sin A5: recv_frame tiene que rechazarlas
    cargar_trama(8'hA5, 8'h04, 8'h01, 8'h00, 8'h01, 8'h05);
    verificar_frame(6, 1'b0);
    cargar_trama(8'h5A, 8'h01, 8'h00, 8'h00, 8'h01, 8'h00);
    verificar_frame(1, 1'b0);

    tb_finish;
  end
endmodule
