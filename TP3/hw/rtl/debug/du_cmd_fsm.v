`include "du_defs.vh"

// Interprete de comandos de la Debug Unit (US-403): por cada byte de comando decide si es
// un comando, si vale en el estado actual (docs/protocolo.md seccion 4.1) y que responder.
//
// Hay dos registros de estado:
//   r_estado  estado del PROTOCOLO (IDLE, READY, RUN...): lo ve la PC en el snapshot y los LEDs
//   r_ctrl    paso INTERNO de la FSM (esperar comando, esperar que salga la respuesta)
// Mientras se responde un NACK, r_estado no cambia ("sin cambiar nada", seccion 4.1).
module du_cmd_fsm #(
    parameter NBIT = 8
  )(
    input wire clock,
    input wire i_reset,
    input wire i_rx_done, // Se avisa que se recibio algo de la UART RX
    input wire [NBIT-1:0] i_rx_data, //El dato que se recibe por UART RX
    output wire o_resp_send, // Señal para enviar una respuesta, va a resp_tx (para respuestas cortas)
    output wire [NBIT-1:0] o_resp_tipo, // Tipo de respuesta (ACK, NACK,PING)
    output wire [NBIT-1:0] o_resp_codigo, // Codigo de respuesta, para NACK
    input wire i_resp_done, // Ya se envio la respuesta, lo manda resp_tx
    output wire [3:0] o_estado // Estado del protocolo -> Leds en top
  );

  function es_comando;
    input [NBIT-1:0] cmd;
    case(cmd)
      `DU_CMD_LOAD, `DU_CMD_RUN,`DU_CMD_STEP, `DU_CMD_DUMP, `DU_CMD_RESET, `DU_CMD_ABORT, `DU_CMD_PING, `DU_CMD_DUMP_MEM:
        es_comando=1'b1;
      default:
        es_comando=1'b0;
    endcase
  endfunction

  // Tabla de docs/protocolo.md. Solo se consulta con un comando conocido.
  // LOADING y DUMPING no interpretan comandos (los bytes son argumentos o se descartan).
  function es_valido;
    input [3:0]      estado;
    input [NBIT-1:0] cmd;
    if (cmd == `DU_CMD_PING)
      es_valido = 1'b1;                                  // PING vale en todos
    else
    case (estado)
      `DU_ESTADO_IDLE,
      `DU_ESTADO_HALTED:
        es_valido = (cmd == `DU_CMD_LOAD) || (cmd == `DU_CMD_RESET) ||
        (cmd == `DU_CMD_DUMP) || (cmd == `DU_CMD_DUMP_MEM);
      `DU_ESTADO_READY,
      `DU_ESTADO_STEPPING:
        es_valido = (cmd != `DU_CMD_ABORT);            // todo salvo ABORT
      `DU_ESTADO_RUN:
        es_valido = (cmd == `DU_CMD_ABORT);
      default:
        es_valido = 1'b0;
    endcase
  endfunction

  // Paso interno de la FSM
  localparam [1:0]
             ESPERA_CMD   = 2'd0,  // esperando un byte de comando
             RESPONDIENDO = 2'd1;  // du_resp_tx esta mandando la respuesta

  reg [3:0]      r_estado;
  reg [1:0]      r_ctrl;
  reg            r_resp_send;
  reg [NBIT-1:0] r_resp_tipo, r_resp_codigo;

  // --- Respuesta al byte recibido (combinacional; se registra con i_rx_done) ---------------
  // El orden importa: un byte desconocido es ERR_DESCONOCIDO aunque no valga en el estado.
  reg [NBIT-1:0] w_tipo, w_codigo;
  always @(*)
  begin
    w_tipo   = `DU_TIPO_ACK;
    w_codigo = 8'h00;
    if (!es_comando(i_rx_data))
    begin
      w_tipo   = `DU_TIPO_NACK;
      w_codigo = `DU_ERR_DESCONOCIDO;
    end
    else if (!es_valido(r_estado, i_rx_data))
    begin
      w_tipo   = `DU_TIPO_NACK;
      w_codigo = `DU_ERR_ESTADO;
    end
    else if (i_rx_data == `DU_CMD_PING)
    begin
      w_tipo   = `DU_TIPO_PING_INFO;
      w_codigo = `DU_PROTO_VERSION;
    end
    // TODO(P4): despachar LOAD, RESET, RUN, STEP, DUMP, DUMP_MEM y ABORT a su submodulo
    // (o_req_*/i_done_*). Mientras tanto responden ACK para que todo comando tenga respuesta.
  end

  // --- Estado ------------------------------------------------------------------------------
  // o_resp_send sale de un registro.
  always @(posedge clock)
    if (i_reset)
    begin
      r_estado      <= `DU_ESTADO_IDLE;
      r_ctrl        <= ESPERA_CMD;
      r_resp_send   <= 1'b0;
      r_resp_tipo   <= 8'h00;
      r_resp_codigo <= 8'h00;
    end
    else
    begin
      r_resp_send <= 1'b0;                 // pulso de un solo ciclo
      case (r_ctrl)
        ESPERA_CMD:
          if (i_rx_done)
          begin
            r_resp_send   <= 1'b1;
            r_resp_tipo   <= w_tipo;
            r_resp_codigo <= w_codigo;
            r_ctrl        <= RESPONDIENDO;
          end
        RESPONDIENDO:                      // los bytes que lleguen aca se ignoran (seccion 7.4)
          if (i_resp_done)
            r_ctrl <= ESPERA_CMD;
        default:
          r_ctrl <= ESPERA_CMD;
      endcase
    end

  assign o_resp_send   = r_resp_send;
  assign o_resp_tipo   = r_resp_tipo;
  assign o_resp_codigo = r_resp_codigo;
  assign o_estado      = r_estado;

endmodule
