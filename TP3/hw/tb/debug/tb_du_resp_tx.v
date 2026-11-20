`timescale 1ns / 1ps

// Prueba de du_resp_tx (US-403, P2) con du_tx_mux y uart_tx reales: las 9 respuestas fijas
// de docs/protocolo.md (seccion 8.1) llegan al host model byte a byte (AC5), o_done es un
// solo pulso, las entradas se copian al pedir el envio y dos respuestas seguidas no se pisan.
module tb_du_resp_tx;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam COUNT_MAX = 4;  // baud rapido: 64 ciclos por bit

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  reg        r_send = 1'b0;
  reg  [7:0] r_tipo = 8'h00, r_codigo = 8'h00;
  wire       w_done;
  wire       w_start_0, w_done_0, w_tx_start, w_tx_done, w_s_tick;
  wire [7:0] w_data_0, w_tx_data;
  reg        r_ok;

  du_resp_tx u_resp (
    .clock(clock), .i_reset(i_reset), .i_send(r_send), .i_tipo(r_tipo), .i_codigo(r_codigo),
    .o_done(w_done), .o_tx_start(w_start_0), .o_tx_data(w_data_0), .i_tx_done(w_done_0)
  );

  // verilator lint_off PINCONNECTEMPTY
  du_tx_mux u_mux (
    .i_sel(1'b0),
    .i_start_0(w_start_0), .i_data_0(w_data_0), .o_done_0(w_done_0),
    .i_start_1(1'b0), .i_data_1(8'h00), .o_done_1(),
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

  integer n_done = 0;
  always @(posedge clock)
    if (w_done)
      n_done = n_done + 1;

  // Pulso de i_send y despues basura en las entradas: la trama tiene que salir con lo copiado
  task pedir;
    input [7:0] tipo;
    input [7:0] codigo;
    begin
      @(negedge clock);
      r_tipo   = tipo;
      r_codigo = codigo;
      r_send   = 1'b1;
      @(negedge clock);
      r_send   = 1'b0;
      r_tipo   = 8'hEE;
      r_codigo = 8'hEE;
    end
  endtask

  // Vuelve en el ciclo del pulso de o_done; si un byte se pierde la FSM queda en WAIT para
  // siempre, asi que hay un limite (holgado: 8 bytes) para que el test falle y no se cuelgue.
  task esperar_done;
    integer c;
    begin
      c = 0;
      while (!w_done && c < 8 * 11 * host_ciclos_bit)
      begin
        @(negedge clock);
        c = c + 1;
      end
      if (!w_done)
        tb_timeout("du_resp_tx no termino la trama");
    end
  endtask

  // Manda una respuesta y verifica lo que recibe el host. len = 0 (ACK) o 1.
  task verificar;
    input [7:0] tipo;
    input [7:0] codigo;
    input integer len;
    integer done_antes;
    begin
      done_antes = n_done;
      fork
        begin
          pedir(tipo, codigo);
          esperar_done;
          @(negedge clock);  // el posedge que cuenta el pulso ya paso
        end
        recv_frame(r_ok);
      join
      check_eq("trama valida (A5 y checksum)", {31'd0, r_ok}, 32'd1);
      check_eq("tipo", {24'd0, host_tipo}, {24'd0, tipo});
      check_eq("longitud", {16'd0, host_len}, len);
      if (len == 1)
        check_eq("payload", {24'd0, host_payload[0]}, {24'd0, codigo});
      check_eq("o_done: un solo pulso", n_done - done_antes, 1);
    end
  endtask

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);

    // docs/protocolo.md seccion 8.1
    verificar(`DU_TIPO_ACK, 8'h77, 0);  // el codigo se ignora en ACK
    verificar(`DU_TIPO_NACK, `DU_ERR_DESCONOCIDO, 1);
    verificar(`DU_TIPO_NACK, `DU_ERR_ESTADO, 1);
    verificar(`DU_TIPO_NACK, `DU_ERR_CHECKSUM, 1);
    verificar(`DU_TIPO_NACK, `DU_ERR_TAMANO, 1);
    verificar(`DU_TIPO_NACK, `DU_ERR_RANGO, 1);
    verificar(`DU_TIPO_NACK, `DU_ERR_TIMEOUT, 1);
    verificar(`DU_TIPO_NACK, `DU_ERR_PARIDAD, 1);
    verificar(`DU_TIPO_PING_INFO, `DU_PROTO_VERSION, 1);

    // Dos respuestas pegadas: la segunda se pide en el ciclo siguiente al o_done
    fork
      begin
        pedir(`DU_TIPO_ACK, 8'h00);
        esperar_done;
        pedir(`DU_TIPO_NACK, `DU_ERR_ESTADO);  // i_send en el ciclo siguiente al o_done
        esperar_done;
      end
      begin
        recv_frame(r_ok);
        check_eq("seguidas: 1ra valida", {31'd0, r_ok}, 32'd1);
        check_eq("seguidas: 1ra es ACK", {24'd0, host_tipo}, 32'h01);
        recv_frame(r_ok);
        check_eq("seguidas: 2da valida", {31'd0, r_ok}, 32'd1);
        check_eq("seguidas: 2da es NACK", {24'd0, host_tipo}, 32'h02);
        check_eq("seguidas: codigo", {24'd0, host_payload[0]}, 32'h02);
      end
    join

    // Despues de la trama la linea queda en reposo y no sale nada mas
    recv_frame(r_ok);
    check_eq("sin pedido no sale nada", {31'd0, r_ok}, 32'd0);

    tb_finish;
  end
endmodule
