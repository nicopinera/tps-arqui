`include "du_defs.vh"

// Serializador de las tramas largas: SNAPSHOT (US-405) y MEM_DATA (US-408).
//
// SNAPSHOT. Con un pulso de i_req_dump manda por el canal 1 de du_tx_mux la trama:
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
// MEM_DATA (DUMP_MEM). Con un pulso de i_req_dump_mem valida el rango pedido
// (protocolo.md 3: direccion multiplo de 4, n >= 1, dir/4 + n <= DMEM_DEPTH) y:
//   - si esta mal, no manda nada: o_done con o_err = ERR_RANGO (du_cmd_fsm responde el NACK);
//   - si esta bien, manda
//
//   A5 | 05 | longitud LE (4 + 4n) | dir (2, LE) | n (2, LE) | n palabras (4 c/u, LE) | XOR
//
//     con dir tal como llego (en bytes) y las palabras dir/4, dir/4 + 1, ..., usadas o no.
//
// El nucleo esta congelado durante todo el volcado: las lecturas de depuracion son combinacionales y valen lo mismo de principio a fin.
//
// Organizacion:
//   1. FSM chica (IDLE, BUSCAR, ENVIAR, ESPERAR, FIN) y sus registros: un byte por vuelta.
//      Es la misma para las dos tramas; r_modo dice cual se esta mandando.
//   2. r_pos dice que byte de la trama va saliendo (0 = A5)
//   3. tabla: que byte corresponde a cada r_pos (copia de protocolo.md 6.1 y 6.2)

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
    input  wire                i_req_dump_mem,// Pulso: mandar un MEM_DATA con i_dm_addr e i_dm_n
    input  wire [15:0]         i_dm_addr,     // Argumentos de DUMP_MEM: direccion en bytes
    input  wire [15:0]         i_dm_n,        // y cantidad de palabras
    output wire                o_done,        // Pulso: salio el ultimo byte (el checksum), o se rechazo el DUMP_MEM
    output wire [NBIT-1:0]     o_err,         // Junto con o_done: 0 = ok, ERR_RANGO = DUMP_MEM fuera de rango

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
  // La FSM solo sabe preparar un byte, mandarlo y esperar a que salga. En que parte de la
  // trama se esta lo dice r_pos, no el estado.
  localparam [2:0]
             IDLE    = 3'd0,  // esperando un pedido
             BUSCAR  = 3'd1,  // antes de cada byte: si empieza una palabra de memoria, busca la proxima usada
             ENVIAR  = 3'd2,  // un ciclo: o_tx_start con el byte de r_pos
             ESPERAR = 3'd3,  // hasta el i_tx_done de ese byte
             FIN     = 3'd4;  // un ciclo: o_done

  localparam [15:0] LEN_FIJO = `DU_SNAPSHOT_FIJO;  // 221: todo el payload menos los 6K de memoria

  // Donde empieza cada seccion dentro del payload (protocolo.md 6.2, columna Offset). Cada
  // seccion termina donde empieza la siguiente. El estado (1 B) esta en el offset 0.
  localparam [15:0]
             OFF_CICLOS  = 16'd1,    // 4 B
             OFF_PC      = 16'd5,    // 4 B
             OFF_RIESGOS = 16'd9,    // 1 B
             OFF_REGS    = 16'd10,   // 32 registros x 4 B = 128 B
             OFF_LATCH   = 16'd138,  // IF/ID 13 + ID/EX 31 + EX/MEM 19 + MEM/WB 18 = 81 B
             OFF_K       = 16'd219,  // 2 B
             OFF_MEM     = 16'd221;  // K x [dir 2 B + dato 4 B]

  // ---------------------------------------------------------------------------------------
  // Registros
  // ---------------------------------------------------------------------------------------
  reg [2:0]              state_reg;
  reg [15:0]             r_pos;      // Byte de la trama que va saliendo: 0 = A5, 1 = tipo, 2-3 = len, 4.. payload
  reg [NBIT-1:0]         r_xor;      // XOR de lo ya mandado (sin el A5): es el checksum
  reg [NBIT-1:0]         r_estado;   // i_snap_estado copiado al pedido (la FSM lo da valido en ese ciclo)
  reg [DMEM_ADDR_BITS:0] r_k;        // K copiado al pedido: de el salen la longitud y los 2 B de K
  reg [647:0]            r_latches;  // Copia de los 4 latches al pedido: {MEM/WB, EX/MEM, ID/EX, IF/ID}
  reg [DMEM_ADDR_BITS:0] r_mem_addr; // Palabra de DMEM que se esta mandando o buscando (1 bit mas: 256 = fin)
  reg [2:0]              r_sub;      // Byte dentro de la entrada de memoria: 0-1 = dir, 2-5 = dato
  reg                    r_modo;     // Trama en curso: 0 = SNAPSHOT, 1 = MEM_DATA
  reg [15:0]             r_dm_addr;  // MEM_DATA: direccion pedida (en bytes), copiada al pedido
  reg [15:0]             r_dm_n;     // MEM_DATA: cantidad de palabras, copiada al pedido
  reg [NBIT-1:0]         r_err;      // -> o_err: resultado del ultimo pedido

  // ---------------------------------------------------------------------------------------
  // Cuentas que salen de los registros
  // ---------------------------------------------------------------------------------------
  // longitud = 221 + 6K, con 6K = 4K + 2K (K <= 256: 221 + 1536 = 1757 entra en 16 bits)
  wire [15:0] w_k   = {{(15-DMEM_ADDR_BITS){1'b0}}, r_k};
  wire [15:0] w_len_snap = LEN_FIJO + (w_k << 2) + (w_k << 1);
  // MEM_DATA: 4 + 4n, con n <= 256 ya validado (como mucho 1028)
  wire [15:0] w_len_mem  = 16'd4 + (r_dm_n << 2);
  wire [15:0] w_len      = r_modo ? w_len_mem : w_len_snap;

  // Validacion de DUMP_MEM sobre los argumentos del pedido. La suma dir/4 + n se hace en
  // 17 bits: en 16, n = FFFF con dir = 4 daria 0x0000 y pasaria como valido.
  localparam [16:0] DMEM_DEPTH = 17'd1 << DMEM_ADDR_BITS;
  wire [16:0] w_dm_fin = {3'b000, i_dm_addr[15:2]} + {1'b0, i_dm_n};  // palabra siguiente a la ultima
  wire        w_dm_ok  = (i_dm_addr[1:0] == 2'b00) && (i_dm_n != 16'd0) && (w_dm_fin <= DMEM_DEPTH);

  // Posicion del checksum: despues de A5, tipo, len (4 B) y el payload
  wire [15:0] w_pos_checksum = w_len + 16'd4;

  // Posicion dentro del payload (0 = byte estado). Solo tiene sentido con r_pos >= 4.
  wire [15:0] w_off = r_pos - 16'd4;

  // Posicion dentro de cada seccion. De cada una solo se usan los bits bajos (lo que entra
  // en la seccion): el resto vale cualquier cosa fuera de rango y no se mira.
  /* verilator lint_off UNUSEDSIGNAL */
  wire [15:0] w_rel_ciclos = w_off - OFF_CICLOS;  // 0..3: byte de i_ciclos
  wire [15:0] w_rel_pc     = w_off - OFF_PC;      // 0..3: byte de i_pc
  wire [15:0] w_rel_regs   = w_off - OFF_REGS;    // 0..127: [6:2] registro, [1:0] byte
  wire [15:0] w_rel_latch  = w_off - OFF_LATCH;   // 0..80: byte de r_latches
  wire [15:0] w_rel_k      = w_off - OFF_K;       // 0..1: byte de K
  wire [15:0] w_rel_mw     = w_off - 16'd4;       // MEM_DATA: [9:2] palabra, [1:0] byte
  /* verilator lint_on UNUSEDSIGNAL */

  // MEM_DATA: el byte del payload. Offsets 0-3 = dir y n (LE), despues las palabras.
  // La palabra que se lee es dir/4 + indice; o_dbg_mem_addr la pide (abajo).
  wire [NBIT-1:0] w_byte_mem =
       (w_off == 16'd0) ? r_dm_addr[7:0]  :
       (w_off == 16'd1) ? r_dm_addr[15:8] :
       (w_off == 16'd2) ? r_dm_n[7:0]     :
       (w_off == 16'd3) ? r_dm_n[15:8]    :
       byte_de(i_dbg_mem_data, w_rel_mw[1:0]);
  wire [DMEM_ADDR_BITS-1:0] w_mem_addr_dm = r_dm_addr[DMEM_ADDR_BITS+1:2] + w_rel_mw[DMEM_ADDR_BITS+1:2];

  // Byte k de la copia de latches = r_latches[8k+7:8k]: el bit donde empieza es k * 8
  wire [9:0] w_bit_latch = {w_rel_latch[6:0], 3'b000};

  // Byte de riesgos (offset 9), protocolo.md 6.2: bit 7 en 0
  wire [NBIT-1:0] w_riesgos = {1'b0, i_fwd_b, i_fwd_a, i_flush_id_ex, i_flush_if_id, i_stall};

  // Memoria: el byte que toca es parte de una entrada [dir 2 B | dato 4 B]
  // Solo en SNAPSHOT: en MEM_DATA no se salta nada y las direcciones salen de w_off
  wire w_en_mem = !r_modo && (r_pos >= 16'd4) && (w_off >= OFF_MEM) && (r_pos != w_pos_checksum);
  wire [15:0] w_dir_bytes = {{(14-DMEM_ADDR_BITS){1'b0}}, r_mem_addr[DMEM_ADDR_BITS-1:0], 2'b00};
  wire [1:0]  w_sub_dato  = r_sub[1:0] - 2'd2;  // r_sub 2..5 -> byte 0..3 del dato (en 2 bits: 4-2 = 2, 5-2 = 3)
  wire [DMEM_ADDR_BITS:0] w_mem_addr_sig = r_mem_addr + {{DMEM_ADDR_BITS{1'b0}}, 1'b1};

  // Byte n (0 = el menos significativo) de una palabra de 32 bits: es el bus[8n+7:8n]
  function [NBIT-1:0] byte_de;
    input [NBIT_32-1:0] palabra;
    input [1:0]         n;
    case (n)
      2'd0:    byte_de = palabra[7:0];
      2'd1:    byte_de = palabra[15:8];
      2'd2:    byte_de = palabra[23:16];
      default: byte_de = palabra[31:24];
    endcase
  endfunction

  // El A5 no entra en el checksum, y el checksum no se suma a si mismo
  wire w_suma_xor = (r_pos != 16'd0) && (r_pos != w_pos_checksum);

  // ---------------------------------------------------------------------------------------
  // 1. FSM y registros
  // ---------------------------------------------------------------------------------------
  always @(posedge clock)
    if (i_reset)
    begin
      state_reg  <= IDLE;
      r_pos      <= 16'd0;
      r_xor      <= {NBIT{1'b0}};
      r_estado   <= {NBIT{1'b0}};
      r_k        <= {(DMEM_ADDR_BITS+1){1'b0}};
      r_latches  <= 648'd0;
      r_mem_addr <= {(DMEM_ADDR_BITS+1){1'b0}};
      r_sub      <= 3'd0;
      r_modo     <= 1'b0;
      r_dm_addr  <= 16'd0;
      r_dm_n     <= 16'd0;
      r_err      <= {NBIT{1'b0}};
    end
    else
    case (state_reg)
      // Quieto hasta que la FSM de comandos pide un snapshot (i_req_dump). Ahi saca la foto
      // de lo que podria cambiar despues (estado, K y latches), arranca desde el byte 0 y
      // pasa a BUSCAR.
      IDLE:
        if (i_req_dump)
        begin
          r_estado   <= i_snap_estado;
          r_k        <= i_dbg_used_count;
          r_latches  <= {i_mem_wb, i_ex_mem, i_id_ex, i_if_id};  // IF/ID en los bits bajos: sale primero
          r_pos      <= 16'd0;
          r_xor      <= {NBIT{1'b0}};
          r_mem_addr <= {(DMEM_ADDR_BITS+1){1'b0}};
          r_sub      <= 3'd0;
          r_modo     <= 1'b0;
          r_err      <= {NBIT{1'b0}};
          state_reg  <= BUSCAR;
        end
        // DUMP_MEM: si el rango esta mal no se manda nada, solo o_done con el error
        else if (i_req_dump_mem)
        begin
          if (w_dm_ok)
          begin
            r_dm_addr <= i_dm_addr;
            r_dm_n    <= i_dm_n;
            r_pos     <= 16'd0;
            r_xor     <= {NBIT{1'b0}};
            r_modo    <= 1'b1;
            r_err     <= {NBIT{1'b0}};
            state_reg <= BUSCAR;
          end
          else
          begin
            r_err     <= `DU_ERR_RANGO;
            state_reg <= FIN;
          end
        end

      // Antes de cada byte. Solo hace algo si el byte que toca es el primero de una entrada
      // de memoria (w_en_mem y r_sub = 0) y la palabra r_mem_addr no fue escrita: avanza
      // una direccion por ciclo hasta encontrar una con i_dbg_mem_used = 1. En cualquier
      // otro caso pasa directo a ENVIAR. Si llega al final de la DMEM sin encontrar (el
      // bitmap no coincide con K: no deberia pasar) tambien sigue, para no colgarse.
      BUSCAR:
        if (w_en_mem && r_sub == 3'd0 && !i_dbg_mem_used && !r_mem_addr[DMEM_ADDR_BITS])
          r_mem_addr <= w_mem_addr_sig;
        else
          state_reg <= ENVIAR;

      // Dura un ciclo: o_tx_start = 1 y la UART toma o_tx_data (el byte de r_pos).
      // Ese byte se suma al checksum. Siempre pasa a ESPERAR.
      ENVIAR:
      begin
        if (w_suma_xor)
          r_xor <= r_xor ^ o_tx_data;
        state_reg <= ESPERAR;
      end

      // Quieto hasta que la UART termina el byte (i_tx_done). Si era el checksum, pasa a
      // FIN. Si no, avanza r_pos (y, en memoria, el byte de la entrada o la palabra) y
      // vuelve a BUSCAR. Ese ENVIAR cae al menos un ciclo despues del done, cuando uart_tx
      // ya salio de STOP.
      ESPERAR:
        if (i_tx_done)
        begin
          if (r_pos == w_pos_checksum)
            state_reg <= FIN;
          else
          begin
            r_pos <= r_pos + 16'd1;
            if (w_en_mem)
            begin
              if (r_sub == 3'd5)
              begin
                r_sub      <= 3'd0;                  // entrada completa: la proxima palabra
                r_mem_addr <= w_mem_addr_sig;        // se busca desde la siguiente direccion
              end
              else
                r_sub <= r_sub + 3'd1;
            end
            state_reg <= BUSCAR;
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
  assign o_err      = r_err;

  // Lecturas de depuracion (combinacionales: el nucleo contesta en el mismo ciclo)
  assign o_dbg_reg_addr = w_rel_regs[6:2];                         // 4 bytes por registro
  assign o_dbg_mem_addr = r_modo ? w_mem_addr_dm : r_mem_addr[DMEM_ADDR_BITS-1:0];

  // ---------------------------------------------------------------------------------------
  // 2. Tabla: que byte sale en cada posicion de la trama (protocolo.md 6 y 6.2)
  // ---------------------------------------------------------------------------------------
  // Cada condicion pregunta "estoy antes de que empiece la seccion siguiente?": que ya se
  // paso el comienzo de la propia lo garantizan las condiciones de arriba.
  always @(*)
    if (r_pos == w_pos_checksum)
      o_tx_data = r_xor;
    else if (r_pos < 16'd4)                  // sobre: A5, tipo, longitud LE
    case (r_pos[1:0])
      2'd0:
        o_tx_data = `DU_SYNC;
      2'd1:
        o_tx_data = r_modo ? `DU_TIPO_MEM_DATA : `DU_TIPO_SNAPSHOT;
      2'd2:
        o_tx_data = w_len[7:0];
      default:
        o_tx_data = w_len[15:8];
    endcase
    else if (r_modo)                         // MEM_DATA: payload entero en w_byte_mem
      o_tx_data = w_byte_mem;
    else if (w_off < OFF_CICLOS)            // offset 0
      o_tx_data = r_estado;
    else if (w_off < OFF_PC)                 // offsets 1..4
      o_tx_data = byte_de(i_ciclos, w_rel_ciclos[1:0]);
    else if (w_off < OFF_RIESGOS)            // offsets 5..8
      o_tx_data = byte_de(i_pc, w_rel_pc[1:0]);
    else if (w_off < OFF_REGS)               // offset 9
      o_tx_data = w_riesgos;
    else if (w_off < OFF_LATCH)              // offsets 10..137: registro o_dbg_reg_addr
      o_tx_data = byte_de(i_dbg_reg_data, w_rel_regs[1:0]);
    else if (w_off < OFF_K)                  // offsets 138..218
      o_tx_data = r_latches[w_bit_latch +: 8];
    else if (w_off < OFF_MEM)                // offsets 219..220: K LE
      o_tx_data = w_rel_k[0] ? w_k[15:8] : w_k[7:0];
    else                                     // offsets 221..: entrada de memoria
    case (r_sub)
      3'd0:
        o_tx_data = w_dir_bytes[7:0];        // direccion en bytes, LE
      3'd1:
        o_tx_data = w_dir_bytes[15:8];
      default:
        o_tx_data = byte_de(i_dbg_mem_data, w_sub_dato);  // dato LE
    endcase

endmodule
