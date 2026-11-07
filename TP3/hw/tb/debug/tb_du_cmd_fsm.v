`timescale 1ns / 1ps

// Prueba del interprete de comandos (US-403) a traves de la UART, como en la placa:
// host model -> uart_rx -> debug_unit -> uart_tx -> host model.
//   AC1  PING responde PING_INFO con la version
//   AC2  STEP en IDLE responde NACK(ERR_ESTADO) y el estado no cambia
//   AC3  un byte desconocido responde NACK(ERR_DESCONOCIDO)
// y ademas recorre los 256 valores de byte en IDLE.
module tb_du_cmd_fsm;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam COUNT_MAX = 4;  // baud rapido: 64 ciclos por bit

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  wire       w_s_tick, w_rx_done, w_parity_err, w_tx_start, w_tx_done;
  wire [7:0] w_rx_data, w_tx_data;
  wire [3:0] w_estado;
  reg        r_ok;

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_rx u_rx (
    .clock(clock), .i_reset(i_reset), .rx(host_tx), .i_s_tick(w_s_tick),
    .o_rx_done(w_rx_done), .o_parity_err(w_parity_err), .o_dout(w_rx_data)
  );

  debug_unit u_du (
    .clock(clock), .i_reset(i_reset),
    .i_rx_done(w_rx_done), .i_rx_data(w_rx_data),
    .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done),
    .o_estado(w_estado)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(w_tx_start), .i_din(w_tx_data), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  always #5 clock = ~clock;

  // Manda un byte y recibe la respuesta en paralelo (la respuesta puede empezar antes de
  // que send_byte termine el bit de stop).
  task comando;
    input [7:0] cmd;
    begin
      fork
        send_byte(cmd);
        recv_frame(r_ok);
      join
    end
  endtask

  task verificar_resp;
    input [7:0]   cmd;
    input [7:0]   tipo;
    input integer len;
    input [7:0]   payload;
    begin
      comando(cmd);
      check_eq("respuesta valida (A5 y checksum)", {31'd0, r_ok}, 32'd1);
      check_eq("tipo de respuesta", {24'd0, host_tipo}, {24'd0, tipo});
      check_eq("longitud", {16'd0, host_len}, len);
      if (len == 1)
        check_eq("payload", {24'd0, host_payload[0]}, {24'd0, payload});
    end
  endtask

  // Respuesta esperada en IDLE para cualquier byte (tabla 4.1, columna IDLE).
  // LOAD, RESET, DUMP y DUMP_MEM responden ACK provisorio hasta P4.
  reg [7:0] esp_tipo, esp_codigo;
  integer   esp_len;
  task esperado_en_idle;
    input [7:0] b;
    begin
      esp_len = 1;
      case (b)
        `DU_CMD_PING:
        begin
          esp_tipo = `DU_TIPO_PING_INFO; esp_codigo = `DU_PROTO_VERSION;
        end
        `DU_CMD_LOAD, `DU_CMD_RESET, `DU_CMD_DUMP, `DU_CMD_DUMP_MEM:
        begin
          esp_tipo = `DU_TIPO_ACK; esp_codigo = 8'h00; esp_len = 0;
        end
        `DU_CMD_RUN, `DU_CMD_STEP, `DU_CMD_ABORT:
        begin
          esp_tipo = `DU_TIPO_NACK; esp_codigo = `DU_ERR_ESTADO;
        end
        default:
        begin
          esp_tipo = `DU_TIPO_NACK; esp_codigo = `DU_ERR_DESCONOCIDO;
        end
      endcase
    end
  endtask

  integer b;
  integer errores_antes;

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);
    check_eq("arranca en IDLE", {28'd0, w_estado}, {28'd0, `DU_ESTADO_IDLE});

    // AC1 (docs/protocolo.md 8.4): 3F -> A5 04 01 00 01 04
    verificar_resp(`DU_CMD_PING, `DU_TIPO_PING_INFO, 1, `DU_PROTO_VERSION);

    // AC2 (8.10): 53 en IDLE -> A5 02 01 00 02 01, sin cambiar el estado
    verificar_resp(`DU_CMD_STEP, `DU_TIPO_NACK, 1, `DU_ERR_ESTADO);
    check_eq("STEP en IDLE: sigue en IDLE", {28'd0, w_estado}, {28'd0, `DU_ESTADO_IDLE});

    // AC3 (8.10): 5A ('Z') -> A5 02 01 00 01 02
    verificar_resp(8'h5A, `DU_TIPO_NACK, 1, `DU_ERR_DESCONOCIDO);

    // Despues de los errores la Debug Unit sigue respondiendo
    verificar_resp(`DU_CMD_PING, `DU_TIPO_PING_INFO, 1, `DU_PROTO_VERSION);

    // Los 256 valores de byte en IDLE: solo los 8 comandos se reconocen.
    // Se informa un resumen para no llenar el log con 1000 chequeos.
    errores_antes = tb_errors;
    for (b = 0; b < 256; b = b + 1)
    begin
      esperado_en_idle(b[7:0]);
      comando(b[7:0]);
      if (!r_ok || host_tipo !== esp_tipo || host_len !== esp_len ||
          (esp_len == 1 && host_payload[0] !== esp_codigo))
      begin
        tb_errors = tb_errors + 1;
        $display("  [FALLA] byte 0x%02h: tipo %02h len %0d payload %02h (esperado %02h %0d %02h)",
                 b[7:0], host_tipo, host_len, host_payload[0], esp_tipo, esp_len, esp_codigo);
      end
    end
    check_eq("256 bytes en IDLE sin errores", tb_errors - errores_antes, 0);
    check_eq("sigue en IDLE", {28'd0, w_estado}, {28'd0, `DU_ESTADO_IDLE});

    tb_finish;
  end
endmodule
