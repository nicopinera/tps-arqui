`include "du_defs.vh"

// Serializador de respuestas cortas de la Debug Unit: con un pulso de i_send manda
// por la UART una trama completa de docs/protocolo.md:
//
//   ACK                 A5 01 00 00 XOR            (5 bytes, sin payload)
//   NACK(codigo)        A5 02 01 00 codigo XOR     (6 bytes)
//   PING_INFO(version)  A5 04 01 00 version XOR    (6 bytes)
//
// XOR = tipo ^ len_lo ^ len_hi ^ payload (el A5 no entra). Las tramas largas (SNAPSHOT,
// MEM_DATA) las arma du_dumper por el otro canal de du_tx_mux.
module du_resp_tx (
    input  wire       clock,
    input  wire       i_reset,
    input  wire       i_send,      // pulso: empezar a mandar la trama
    input  wire [7:0] i_tipo,      // DU_TIPO_ACK, DU_TIPO_NACK o DU_TIPO_PING_INFO
    input  wire [7:0] i_codigo,    // codigo de error (NACK) o version (PING_INFO); ACK lo ignora
    output reg        o_done,      // pulso de 1 ciclo: salio el ultimo byte
    output reg        o_tx_start,  // canal 0 de du_tx_mux
    output reg  [7:0] o_tx_data,
    input  wire       i_tx_done
  );
  localparam [1:0]
             IDLE  = 2'b00,
             START = 2'b01,  // un ciclo con o_tx_start = 1
             WAIT  = 2'b10;  // esperar el o_tx_done del byte en vuelo

  reg [1:0] state_reg, state_next;
  reg [2:0] r_idx, r_idx_next;        // byte actual de la trama: 0..5
  reg [7:0] r_tipo, r_codigo;         // copia de las entradas al recibir i_send

  // Campos que salen del tipo: solo ACK va sin payload
  wire       w_con_payload = (r_tipo != `DU_TIPO_ACK); // = 1 si no es ACK, = 0 si es ACK
  wire [7:0] w_len_lo      = {7'd0, w_con_payload};
  wire [7:0] w_payload     = w_con_payload ? r_codigo : 8'h00;
  wire [7:0] w_xor         = r_tipo ^ w_len_lo ^ 8'h00 ^ w_payload;
  wire [2:0] w_ultimo      = w_con_payload ? 3'd5 : 3'd4; // Cuantos byte se mandan segun el tipo

  // --- Estado y registros ---------------------------------------------------------------
  always @(posedge clock)
    if (i_reset)
    begin
      state_reg <= IDLE;
      r_idx     <= 3'd0;
      r_tipo    <= 8'h00;
      r_codigo  <= 8'h00;
    end
    else
    begin
      state_reg <= state_next;
      r_idx     <= r_idx_next;
      if (state_reg == IDLE && i_send) // Si estamos esperando y llega la señal para empezar a enviar
      begin
        r_tipo   <= i_tipo; // Guardamos el tipo que nos llega de la FCM
        r_codigo <= i_codigo; // Guardamos el codigo que nos pasa la FCM
      end
    end

  // --- Proxima transicion y salidas de control ------------------------------------------
  always @(*)
  begin
    state_next = state_reg;
    r_idx_next = r_idx;
    o_tx_start = 1'b0;
    o_done     = 1'b0;

    case (state_reg)
      IDLE:
        if (i_send)
        begin
          r_idx_next = 3'd0;
          state_next = START;
        end
      START:
      begin
        o_tx_start = 1'b1;
        state_next = WAIT;
      end
      WAIT:
        // o_tx_done llega con uart_tx todavia en STOP: el proximo start va un ciclo despues
        // (estado START); si se diera ahora, uart_tx lo ignoraria y el byte se perderia.
        if (i_tx_done)
        begin
          if (r_idx == w_ultimo)
          begin
            o_done     = 1'b1;
            state_next = IDLE;
          end
          else
          begin
            r_idx_next = r_idx + 3'd1;
            state_next = START;
          end
        end
      default:
        state_next = IDLE;
    endcase
  end

  // --- Byte que sale segun el indice -----------------------------------------------------
  always @(*)
  case (r_idx)
    3'd0:
      o_tx_data = `DU_SYNC;
    3'd1:
      o_tx_data = r_tipo;
    3'd2:
      o_tx_data = w_len_lo;
    3'd3:
      o_tx_data = 8'h00;                              // len_hi
    3'd4:
      o_tx_data = w_con_payload ? r_codigo : w_xor;   // ACK: aca ya va el XOR
    default:
      o_tx_data = w_xor;
  endcase

endmodule
