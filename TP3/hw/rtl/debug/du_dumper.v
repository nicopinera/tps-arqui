`include "du_defs.vh"

// Serializador del SNAPSHOT:
// Con un pulso de i_req_dump manda por el canal 1 de du_tx_mux la trama:
//
//   A5 | 03 | longitud LE (221 + 6K) | payload | XOR
//
// longitud = cantidad de bytes del payload. K = palabras de DMEM que escribio el programa
// (i_dbg_used_count); cada una ocupa 6 B en el payload: dir (2) + dato (4).
//
// y el payload, en este orden:
//   estado (1) | ciclos (4) | PC (4) | riesgos (1) | x0..x31 (128) |
//   IF/ID (13) | ID/EX (31) | EX/MEM (19) | MEM/WB (18) | K (2) | K x [dir (2) + dato (4)]
//
// El nucleo esta congelado durante todo el volcado: las lecturas de depuracion son combinacionales y valen lo mismo de principio a fin.
//
// Organizacion:
//   1. FSM chica (IDLE, ENVIAR, ESPERAR, FIN) y sus registros: un byte por vuelta
//   2. r_pos dice que byte de la trama va saliendo (0 = A5)
//   3. tabla: que byte corresponde a cada r_pos (copia de protocolo.md 6.2)

// TODO(nico): sacar este lint_off cuando todas las entradas se usen (P6)
/* verilator lint_off UNUSEDSIGNAL */
module du_dumper #(
    parameter NBIT           = 8,
    parameter NBIT_32        = 32,
    parameter DMEM_ADDR_BITS = 8
  )(
    input  wire clock,
    input  wire i_reset,

    // Hacia CMD_FSM
    input  wire                i_req_dump,    // Pulso: empezar a mandar un SNAPSHOT
    input  wire [NBIT-1:0]     i_snap_estado, // Byte 0 del payload: {motivo, estado de la DU}
    output wire                o_done,        // Pulso: salio el ultimo byte (el checksum)
    output wire [NBIT-1:0]     o_err,         // Siempre 0 en SNAPSHOT; existe por DUMP_MEM (US-408)

    // Hacia EXEC_CTRL (hasta US-406 lo maneja el testbench)
    input  wire [NBIT_32-1:0]  i_ciclos,      // Ciclos con i_enable = 1 desde el ultimo LOAD/RESET

    // Hacia CORE: estado de la arquitectura
    input  wire [NBIT_32-1:0]  i_pc,          // PC actual del nucleo (o_pc)

    // Hacia CORE: lectura de depuracion (combinacional: la respuesta llega en el mismo ciclo)
    output wire [4:0]                o_dbg_reg_addr,   // Registro que se quiere leer (x0..x31)
    input  wire [NBIT_32-1:0]        i_dbg_reg_data,   // Valor del registro pedido
    output wire [DMEM_ADDR_BITS-1:0] o_dbg_mem_addr,   // Palabra de DMEM que se quiere leer
    input  wire [NBIT_32-1:0]        i_dbg_mem_data,   // Dato de esa palabra
    input  wire                      i_dbg_mem_used,   // 1 = el programa escribio esa palabra (bitmap)
    input  wire [DMEM_ADDR_BITS:0]   i_dbg_used_count, // K: cuantas palabras tienen el bit en 1 (0..256)

    // Hacia CORE: senales de riesgo del ciclo (van al byte 9 del payload)
    input  wire                i_stall,       // Stall de load-use
    input  wire                i_flush_if_id, // Burbuja en IF/ID (salto tomado / jal)
    input  wire                i_flush_id_ex, // Burbuja en ID/EX (salto tomado)
    input  wire [1:0]          i_fwd_a,       // Forwarding operando A: 00 banco, 01 MEM/WB, 10 EX/MEM
    input  wire [1:0]          i_fwd_b,       // Idem operando B

    // Hacia CORE: latches como buses planos; byte k = bus[8k+7:8k], se manda primero el 0
    input  wire [103:0]        i_if_id,       // 13 B
    input  wire [247:0]        i_id_ex,       // 31 B
    input  wire [151:0]        i_ex_mem,      // 19 B
    input  wire [143:0]        i_mem_wb,      // 18 B

    // Hacia du_tx_mux (canal 1): mismo handshake que du_resp_tx
    output wire                o_tx_start,    // Pulso: mandar o_tx_data
    output reg  [NBIT-1:0]     o_tx_data,     // Byte a mandar (lo toma uart_tx junto con el start)
    input  wire                i_tx_done      // Pulso: la UART termino el byte en vuelo
  );
  // La FSM solo sabe mandar un byte y esperar a que salga. En que parte de la trama se esta
  // lo dice r_pos, no el estado.
  localparam [1:0]
             IDLE    = 2'd0,  // esperando un pedido
             ENVIAR  = 2'd1,  // un ciclo: o_tx_start con el byte de r_pos
             ESPERAR = 2'd2,  // hasta el i_tx_done de ese byte
             FIN     = 2'd3;  // un ciclo: o_done
  // TODO(US-405 P6): un estado mas (BUSCAR) para saltar las palabras no usadas del bitmap

  localparam [15:0] LEN_FIJO = `DU_SNAPSHOT_FIJO;  // 221: todo el payload menos los 6K de memoria

  reg [1:0]      state_reg;
  reg [15:0]     r_pos;  // Byte de la trama que va saliendo: 0 = A5, 1 = tipo, 2-3 = len, 4.. payload
  reg [NBIT-1:0] r_xor;  // XOR de lo ya mandado (sin el A5): es el checksum
  reg [15:0]     r_len;  // Longitud del payload, fijada al arrancar con el K de la foto

  // longitud = 221 + 6K, con 6K = 4K + 2K (K <= 256: 221 + 1536 = 1757 entra en 16 bits)
  wire [15:0] w_k   = {{(15-DMEM_ADDR_BITS){1'b0}}, i_dbg_used_count};
  wire [15:0] w_len = LEN_FIJO + (w_k << 2) + (w_k << 1);

  // Posicion del checksum: despues de A5, tipo, len (4 B) y el payload
  wire [15:0] w_pos_checksum = 16'd4;  // TODO(US-405 P3): r_len + 16'd4 cuando haya payload

  // El A5 no entra en el checksum, y el checksum no se suma a si mismo
  wire w_suma_xor = (r_pos != 16'd0) && (r_pos != w_pos_checksum);

  // ---------------------------------------------------------------------------------------
  // 1. FSM y registros
  // ---------------------------------------------------------------------------------------
  always @(posedge clock)
    if (i_reset)
    begin
      state_reg <= IDLE;
      r_pos     <= 16'd0;
      r_xor     <= {NBIT{1'b0}};
      r_len     <= 16'd0;
    end
    else
    case (state_reg)
      // Quieto hasta que la FSM de comandos pide un snapshot (i_req_dump). Ahi fija la
      // longitud con el K de este momento, arranca desde el byte 0 y pasa a ENVIAR.
      IDLE:
        if (i_req_dump)
        begin
          r_len     <= w_len;
          r_pos     <= 16'd0;
          r_xor     <= {NBIT{1'b0}};
          state_reg <= ENVIAR;
        end

      // Dura un ciclo: o_tx_start = 1 y la UART toma o_tx_data (el byte de r_pos).
      // Ese byte se suma al checksum. Siempre pasa a ESPERAR.
      ENVIAR:
      begin
        if (w_suma_xor)
          r_xor <= r_xor ^ o_tx_data;
        state_reg <= ESPERAR;
      end

      // Quieto hasta que la UART termina el byte (i_tx_done). Si era el checksum, pasa a
      // FIN; si no, avanza r_pos y vuelve a ENVIAR. Ese ENVIAR cae un ciclo despues del
      // done, cuando uart_tx ya salio de STOP.
      ESPERAR:
        if (i_tx_done)
        begin
          if (r_pos == w_pos_checksum)
            state_reg <= FIN;
          else
          begin
            r_pos     <= r_pos + 16'd1;
            state_reg <= ENVIAR;
          end
        end

      // Dura un ciclo: o_done = 1 avisa a la FSM de comandos. Vuelve a IDLE.
      FIN:
        state_reg <= IDLE;

      default:
        state_reg <= IDLE;
    endcase

  // Salidas que dependen solo del estado
  assign o_tx_start = (state_reg == ENVIAR);
  assign o_done     = (state_reg == FIN);

  assign o_err          = {NBIT{1'b0}};
  assign o_dbg_reg_addr = 5'd0;                    // TODO(US-405 P4): sale de r_pos
  assign o_dbg_mem_addr = {DMEM_ADDR_BITS{1'b0}};  // TODO(US-405 P6): recorrido del bitmap

  // ---------------------------------------------------------------------------------------
  // 2. Tabla: que byte sale en cada posicion de la trama (protocolo.md 6 y 6.2)
  // ---------------------------------------------------------------------------------------
  always @(*)
    if (r_pos == w_pos_checksum)
      o_tx_data = r_xor;
    else
    case (r_pos)
      16'd0:
        o_tx_data = `DU_SYNC;
      16'd1:
        o_tx_data = `DU_TIPO_SNAPSHOT;
      16'd2:
        o_tx_data = r_len[7:0];   // longitud LE: primero el byte bajo
      16'd3:
        o_tx_data = r_len[15:8];
      // TODO(US-405 P3..P6): payload, offset = r_pos - 4 (estado, ciclos, PC, riesgos, registros, latches, K, memoria)
      default:
        o_tx_data = {NBIT{1'b0}};
    endcase

endmodule
/* verilator lint_on UNUSEDSIGNAL */
