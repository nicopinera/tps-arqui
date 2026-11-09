`include "du_defs.vh"

// Interprete de comandos de la Debug Unit: por cada byte de comando decide si es
// un comando, si vale en el estado actual, le pide la accion
// al submodulo que corresponde y responde. Implementa las transiciones de la seccion 5, el
// timeout de recepcion, el error de paridad y el drenado.
//
// Hay dos registros de estado:
//   r_estado  estado del PROTOCOLO (IDLE, READY, RUN...): lo ve la PC y los LEDs
//   r_ctrl    paso INTERNO de la FSM (esperar comando, esperar un submodulo, responder...)
// Mientras se responde un NACK, r_estado no cambia.
//
// Submodulos:
//   du_loader    LOAD y RESET          o_req_load/o_load_byte/o_load_cancel, o_req_reset
//   du_exec_ctrl RUN, STEP y ABORT     o_req_run, o_req_step, o_req_abort
//   du_dumper    SNAPSHOT y MEM_DATA   o_req_dump, o_req_dump_mem (canal 1 de du_tx_mux)
// Los pedidos son pulsos de un ciclo. Las respuestas *_done son pulsos, salvo i_run_fin,
// que es un nivel: el fin de un RUN puede llegar mientras se responde un PING.
module du_cmd_fsm #(
    parameter NBIT        = 8,
    parameter CLK_FREQ_HZ = 100_000_000,
    // Ciclos de silencio en medio de los argumentos antes de responder NACK(ERR_TIMEOUT)
    parameter RX_TIMEOUT_CYCLES = CLK_FREQ_HZ / 1000 * `DU_RX_TIMEOUT_MS
  )(
    input wire clock,
    input wire i_reset,

    // uart_rx
    input wire i_rx_done, // Se avisa que se recibio algo de la UART RX
    input wire [NBIT-1:0] i_rx_data, // El dato que se recibe por UART RX
    input wire i_parity_err, // Llego un byte con la paridad mal (uart_rx lo descarto)

    // du_resp_tx (respuestas cortas: ACK, NACK, PING_INFO)
    output wire o_resp_send, // Señal para enviar una respuesta, va a resp_tx (para respuestas cortas)
    output wire [NBIT-1:0] o_resp_tipo, // Tipo de respuesta (ACK, NACK, PING)
    output wire [NBIT-1:0] o_resp_codigo, // Codigo de respuesta, para NACK
    input wire i_resp_done, // Ya se envio la respuesta, lo manda resp_tx

    // du_tx_mux
    output wire o_tx_sel, // 0 = du_resp_tx, 1 = du_dumper

    // du_loader (LOAD y RESET)
    output wire o_req_load, // Empieza un LOAD
    output wire o_load_byte, // i_rx_data es el proximo byte de la carga
    output wire [NBIT-1:0] o_load_data,
    output wire o_load_cancel, // LOAD cortado (timeout o paridad): rellenar la IMEM con HALT
    input wire i_load_done, // El loader termino (con o sin error)
    input wire [NBIT-1:0] i_load_err, // 0 = ok, `DU_ERR_CHECKSUM o `DU_ERR_TAMANO
    output wire o_req_reset, // RESET: limpiar todo menos la IMEM
    input wire i_reset_done,

    // du_exec_ctrl (RUN, STEP y ABORT) y nucleo
    output wire o_req_run,
    output wire o_req_step,
    output wire o_req_abort,
    input wire i_step_done, // Termino el ciclo del STEP
    input wire i_run_fin, // NIVEL: el RUN termino (HALT o ilegal en WB, o ABORT drenado)

    // du_exec_ctrl lo baja al recibir o_req_run
    input wire i_halted, // o_halted del nucleo
    input wire i_illegal, // o_illegal del nucleo

    // du_dumper (SNAPSHOT y MEM_DATA)
    output wire o_req_dump, // Mandar un SNAPSHOT
    output wire o_req_dump_mem, // Mandar un MEM_DATA con o_dm_addr y o_dm_n
    output wire [15:0] o_dm_addr, // Argumentos de DUMP_MEM: direccion en bytes
    output wire [15:0] o_dm_n, // y cantidad de palabras
    input wire i_dump_done, // El dumper termino (con o sin error)
    input wire [NBIT-1:0] i_dump_err, // 0 = ok, `DU_ERR_RANGO
    output wire [7:0] o_snap_estado, // Byte 0 del snapshot: {motivo, estado de destino}

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

  // Solo se consulta con un comando conocido.
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
  localparam [2:0]
             ESPERA_CMD   = 3'd0,  // esperando un byte de comando (o el fin de un RUN)
             RESPONDIENDO = 3'd1,  // du_resp_tx esta mandando ACK/NACK/PING_INFO
             ESPERA_SUB   = 3'd2,  // esperando el *_done de RESET o STEP
             VOLCANDO     = 3'd3,  // du_dumper esta mandando SNAPSHOT o MEM_DATA
             CARGANDO     = 3'd4,  // los bytes que llegan son la carga del LOAD
             ARGS_MEM     = 3'd5,  // juntando los 4 bytes de argumentos de DUMP_MEM
             DRENANDO     = 3'd6;  // error en medio de los argumentos: descartar hasta silencio

  // Timeout de recepcion: el contador tiene el ancho justo y se compara con el mismo ancho
  localparam integer TO_BITS   = $clog2(RX_TIMEOUT_CYCLES + 1);
  localparam integer TO_LAST_I = RX_TIMEOUT_CYCLES;
  localparam [TO_BITS-1:0] TO_LAST = TO_LAST_I[TO_BITS-1:0];

  reg [3:0]      r_estado;       // estado del protocolo
  reg [3:0]      r_estado_sig;   // estado al terminar la respuesta o el volcado en curso
  reg [3:0]      r_prev;         // estado al que vuelven DUMP y DUMP_MEM
  reg [3:0]      r_motivo;       // motivo de terminacion, viaja en el snapshot
  reg [2:0]      r_ctrl;
  reg [NBIT-1:0] r_cmd;          // comando en curso (LOAD, RESET, STEP, DUMP_MEM...)
  reg [NBIT-1:0] r_err;          // codigo de NACK pendiente mientras se drena
  reg            r_run_pend;     // RUN: pedir la ejecucion cuando termine de salir el ACK
  reg            r_abort;        // llego ABORT: el fin del RUN tiene motivo ABORTED
  reg [1:0]      r_arg_idx;      // byte de argumento de DUMP_MEM que llega (0..3)
  reg [31:0]     r_dm_args;      // {n palabras, direccion}, little-endian como llegan
  reg            r_tx_sel;
  reg [TO_BITS-1:0] r_timer;     // ciclos desde el ultimo byte recibido

  reg            r_resp_send;
  reg [NBIT-1:0] r_resp_tipo, r_resp_codigo;
  reg r_req_load, r_load_cancel, r_req_reset, r_req_run, r_req_step, r_req_abort;
  reg r_req_dump, r_req_dump_mem;

  wire w_byte      = i_rx_done || i_parity_err;   // llego un byte, bueno o malo
  wire w_timeout   = (r_timer == TO_LAST);
  wire w_con_timer = (r_ctrl == CARGANDO) || (r_ctrl == ARGS_MEM) || (r_ctrl == DRENANDO);

  // Motivo segun el nucleo: solo tiene sentido con i_halted = 1
  wire [3:0] w_motivo_nucleo = i_illegal ? `DU_MOTIVO_ILLEGAL : `DU_MOTIVO_HALTED;

  // Arranca una respuesta corta y deja anotado a que estado ir cuando termine de salir
  task responder;
    input [NBIT-1:0] tipo;
    input [NBIT-1:0] codigo;
    input [3:0]      estado_sig;
    begin
      r_resp_send   <= 1'b1;
      r_resp_tipo   <= tipo;
      r_resp_codigo <= codigo;
      r_estado_sig  <= estado_sig;
      r_ctrl        <= RESPONDIENDO;
    end
  endtask

  // Arranca un SNAPSHOT por el canal 1 (el dumper lee o_snap_estado en ese momento)
  task volcar;
    input [3:0] estado_sig;
    begin
      r_req_dump   <= 1'b1;
      r_tx_sel     <= 1'b1;
      r_estado     <= `DU_ESTADO_DUMPING;
      r_estado_sig <= estado_sig;
      r_ctrl       <= VOLCANDO;
    end
  endtask

  // --- Timeout de recepcion -----------------------------------------------------------------
  // Corre solo mientras se esperan argumentos o se drena, y vuelve a 0 con cada byte.
  always @(posedge clock)
    if (i_reset || !w_con_timer || w_byte)
      r_timer <= {TO_BITS{1'b0}};
    else if (!w_timeout)
      r_timer <= r_timer + 1'b1;

  // --- FSM -----------------------------------------------------------------------------------
  // Las salidas hacia otros modulos salen de registros (Moore): si alguna dependiera de un
  // *_done Mealy se armaria un lazo combinacional.
  always @(posedge clock)
    if (i_reset)
    begin
      r_estado       <= `DU_ESTADO_IDLE;
      r_estado_sig   <= `DU_ESTADO_IDLE;
      r_prev         <= `DU_ESTADO_IDLE;
      r_motivo       <= `DU_MOTIVO_NINGUNO;
      r_ctrl         <= ESPERA_CMD;
      r_cmd          <= 8'h00;
      r_err          <= 8'h00;
      r_run_pend     <= 1'b0;
      r_abort        <= 1'b0;
      r_arg_idx      <= 2'd0;
      r_dm_args      <= 32'd0;
      r_tx_sel       <= 1'b0;
      r_resp_send    <= 1'b0;
      r_resp_tipo    <= 8'h00;
      r_resp_codigo  <= 8'h00;
      r_req_load     <= 1'b0;
      r_load_cancel  <= 1'b0;
      r_req_reset    <= 1'b0;
      r_req_run      <= 1'b0;
      r_req_step     <= 1'b0;
      r_req_abort    <= 1'b0;
      r_req_dump     <= 1'b0;
      r_req_dump_mem <= 1'b0;
    end
    else
    begin
      // Pulsos de un solo ciclo
      r_resp_send    <= 1'b0;
      r_req_load     <= 1'b0;
      r_load_cancel  <= 1'b0;
      r_req_reset    <= 1'b0;
      r_req_run      <= 1'b0;
      r_req_step     <= 1'b0;
      r_req_abort    <= 1'b0;
      r_req_dump     <= 1'b0;
      r_req_dump_mem <= 1'b0;

      case (r_ctrl)
        // ---------------------------------------------------------------------------------
        ESPERA_CMD:
          // En el ciclo de o_req_run, i_run_fin todavia puede ser el del RUN anterior
          if (r_estado == `DU_ESTADO_RUN && i_run_fin && !r_req_run)
          begin
            // Fin del RUN (o del drenado de ABORT): snapshot final y a HALTED
            r_motivo <= r_abort ? `DU_MOTIVO_ABORTED : w_motivo_nucleo;
            r_abort  <= 1'b0;
            volcar(`DU_ESTADO_HALTED);
          end
          else if (i_parity_err)
            // Byte de comando con la paridad mal: no hay argumentos que drenar. En RUN la
            // ejecucion sigue (seccion 7.2).
            responder(`DU_TIPO_NACK, `DU_ERR_PARIDAD, r_estado);
          else if (i_rx_done)
          begin
            // El orden importa: un byte desconocido es ERR_DESCONOCIDO aunque no valga aca
            if (!es_comando(i_rx_data))
              responder(`DU_TIPO_NACK, `DU_ERR_DESCONOCIDO, r_estado);
            else if (!es_valido(r_estado, i_rx_data))
              responder(`DU_TIPO_NACK, `DU_ERR_ESTADO, r_estado);
            else
            begin
              r_cmd <= i_rx_data;
              case (i_rx_data)
                `DU_CMD_PING:
                  responder(`DU_TIPO_PING_INFO, `DU_PROTO_VERSION, r_estado);
                `DU_CMD_LOAD:
                begin
                  r_estado   <= `DU_ESTADO_LOADING;
                  r_motivo   <= `DU_MOTIVO_NINGUNO;
                  r_req_load <= 1'b1;
                  r_ctrl     <= CARGANDO;
                end
                `DU_CMD_RESET:
                begin
                  r_req_reset <= 1'b1;
                  r_ctrl      <= ESPERA_SUB;
                end
                `DU_CMD_RUN:
                begin
                  // Primero sale el ACK; la ejecucion se pide cuando termina (r_run_pend),
                  // asi el snapshot final nunca compite con el ACK por la UART.
                  r_run_pend <= 1'b1;
                  responder(`DU_TIPO_ACK, 8'h00, `DU_ESTADO_RUN);
                end
                `DU_CMD_STEP:
                begin
                  r_req_step <= 1'b1;
                  r_ctrl     <= ESPERA_SUB;
                end
                `DU_CMD_DUMP:
                begin
                  r_prev <= r_estado;
                  volcar(r_estado);
                end
                `DU_CMD_DUMP_MEM:
                begin
                  r_prev    <= r_estado;
                  r_estado  <= `DU_ESTADO_DUMPING;
                  r_arg_idx <= 2'd0;
                  r_ctrl    <= ARGS_MEM;
                end
                `DU_CMD_ABORT:
                begin
                  // Sin respuesta inmediata: la respuesta es el snapshot cuando termine el
                  // drenado (i_run_fin). Mientras tanto se sigue en RUN escuchando PING.
                  r_abort     <= 1'b1;
                  r_req_abort <= 1'b1;
                end
                default:
                  ;
              endcase
            end
          end

        // ---------------------------------------------------------------------------------
        RESPONDIENDO:                      // los bytes que lleguen aca se ignoran (seccion 7.4)
          if (i_resp_done)
          begin
            r_estado <= r_estado_sig;
            r_ctrl   <= ESPERA_CMD;
            if (r_run_pend)
            begin
              r_req_run  <= 1'b1;
              r_run_pend <= 1'b0;
            end
          end

        // ---------------------------------------------------------------------------------
        ESPERA_SUB:
          if (r_cmd == `DU_CMD_RESET && i_reset_done)
          begin
            // RESET sin programa cargado queda en IDLE (seccion 4.1, nota 1)
            r_motivo <= `DU_MOTIVO_NINGUNO;
            responder(`DU_TIPO_ACK, 8'h00,
                      (r_estado == `DU_ESTADO_IDLE) ? `DU_ESTADO_IDLE : `DU_ESTADO_READY);
          end
          else if (r_cmd == `DU_CMD_STEP && i_step_done)
          begin
            // Si en ese ciclo el HALT o una ilegal llego a WB, la ejecucion termino
            r_motivo <= i_halted ? w_motivo_nucleo : `DU_MOTIVO_NINGUNO;
            volcar(i_halted ? `DU_ESTADO_HALTED : `DU_ESTADO_STEPPING);
          end

        // ---------------------------------------------------------------------------------
        VOLCANDO:
          if (i_dump_done)
          begin
            r_tx_sel <= 1'b0;              // el canal 0 recupera la UART entre tramas
            if (i_dump_err != 8'h00)
              responder(`DU_TIPO_NACK, i_dump_err, r_estado_sig);  // ERR_RANGO
            else
            begin
              r_estado <= r_estado_sig;
              r_ctrl   <= ESPERA_CMD;
            end
          end

        // ---------------------------------------------------------------------------------
        CARGANDO:                          // o_load_byte reenvia cada byte (abajo)
          if (i_parity_err)
          begin
            r_err         <= `DU_ERR_PARIDAD;
            r_load_cancel <= 1'b1;
            r_ctrl        <= DRENANDO;
          end
          else if (i_load_done)
          begin
            if (i_load_err == 8'h00)
              responder(`DU_TIPO_ACK, 8'h00, `DU_ESTADO_READY);
            else
            begin
              // ERR_TAMANO llega despues de N, con la carga todavia entrando: drenar
              r_err  <= i_load_err;
              r_ctrl <= DRENANDO;
            end
          end
          else if (w_timeout)
          begin
            r_load_cancel <= 1'b1;
            responder(`DU_TIPO_NACK, `DU_ERR_TIMEOUT, `DU_ESTADO_IDLE);
          end

        // ---------------------------------------------------------------------------------
        ARGS_MEM:
          if (i_parity_err)
          begin
            r_err  <= `DU_ERR_PARIDAD;
            r_ctrl <= DRENANDO;
          end
          else if (i_rx_done)
          begin
            r_dm_args[8*r_arg_idx +: 8] <= i_rx_data;
            r_arg_idx <= r_arg_idx + 2'd1;
            if (r_arg_idx == 2'd3)
            begin
              // El dumper valida el rango: o manda MEM_DATA o vuelve con ERR_RANGO
              r_req_dump_mem <= 1'b1;
              r_tx_sel       <= 1'b1;
              r_estado_sig   <= r_prev;
              r_ctrl         <= VOLCANDO;
            end
          end
          else if (w_timeout)
            responder(`DU_TIPO_NACK, `DU_ERR_TIMEOUT, r_prev);

        // ---------------------------------------------------------------------------------
        DRENANDO:                          // los bytes se descartan; cada uno reinicia el timer
          if (w_timeout && !w_byte)
            responder(`DU_TIPO_NACK, r_err,
                      (r_cmd == `DU_CMD_LOAD) ? `DU_ESTADO_IDLE : r_prev);

        default:
          r_ctrl <= ESPERA_CMD;
      endcase
    end

  assign o_resp_send    = r_resp_send;
  assign o_resp_tipo    = r_resp_tipo;
  assign o_resp_codigo  = r_resp_codigo;
  assign o_tx_sel       = r_tx_sel;

  // El byte de la carga sale en el mismo ciclo que llega (o_dout de uart_rx es un registro).
  // shortcut: o_load_cancel no espera respuesta del loader; el relleno con HALT (256 ciclos)
  // tiene que terminar antes de que salga el NACK (~3 ms). Si el loader tarda mas, agregar
  // un i_cancel_done y esperarlo.
  assign o_req_load     = r_req_load;
  assign o_load_byte    = (r_ctrl == CARGANDO) && i_rx_done;
  assign o_load_data    = i_rx_data;
  assign o_load_cancel  = r_load_cancel;
  assign o_req_reset    = r_req_reset;

  assign o_req_run      = r_req_run;
  assign o_req_step     = r_req_step;
  assign o_req_abort    = r_req_abort;

  assign o_req_dump     = r_req_dump;
  assign o_req_dump_mem = r_req_dump_mem;
  assign o_dm_addr      = r_dm_args[15:0];
  assign o_dm_n         = r_dm_args[31:16];
  assign o_snap_estado  = {r_motivo, r_estado_sig};

  assign o_estado       = r_estado;

endmodule
