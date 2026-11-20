`include "du_defs.vh"

module du_loader #(
    parameter NBIT = 8,
    parameter NBIT_32 = 32,
    parameter IMEM_ADDR_BITS = 8,
    parameter DMEM_ADDR_BITS = 8
  )(
    input wire clock,
    input wire i_reset,

    // Hacia CMD_FSM
    input wire i_req_load, // Da inicio al LOAD
    input wire i_load_byte, // Pulso de que empezo el siguiente byte
    input wire [NBIT-1:0] i_load_data, // El dato/byte
    input wire i_load_cancel, // Pulso de que se corto la carga
    output reg o_done, // Pulso: Finalizo la carga
    output reg [NBIT-1:0] o_err, // Codigo de error
    input wire i_req_reset, // Pulso: RESET
    output reg o_reset_done, // Pulso: Finalizo el RESET

    // Hacia CORE
    output reg o_imem_we,
    output reg [IMEM_ADDR_BITS-1:0] o_imem_addr,
    output reg [NBIT_32-1:0] o_imem_wdata,
    output reg o_dmem_we, // Escribe 0 en o_dmem_addr
    output reg [DMEM_ADDR_BITS-1:0] o_dmem_addr,
    output reg o_clear_used, // Borra el bitmap y el contador de memoria usada
    output reg o_flush_all, // Pipeline vacio, PC = 0, registros en 0

    // Hacia EXEC_CTRL
    output reg o_load_done
  );
  localparam [2:0]
             IDLE = 3'd0,
             LEN_LO = 3'd1,
             LEN_HI = 3'd2,
             PALABRAS = 3'd3,
             CHECKSUM = 3'd4,
             LIMPIAR = 3'd5,
             FIN = 3'd6;

  // Quien pidio la limpieza: decide que hace LIMPIAR y a quien avisa FIN
  localparam [1:0]
             ORIG_LOAD = 2'd0,   // HALT desde r_inicio; avisa con o_done
             ORIG_RESET = 2'd1,  // no toca la IMEM; avisa con o_reset_done
             ORIG_CANCEL = 2'd2; // HALT en toda la IMEM; no avisa

  reg [2:0] r_state;
  reg [1:0] r_origen;
  reg [8:0] r_n;           // N ya validado (1..256); el N completo de 16 bits es w_n
  reg [NBIT_32-NBIT-1:0] r_word; // Los 3 bytes ya llegados de la palabra en curso
  reg [1:0] r_byte_idx;    // Byte de la palabra que va llegando: 0..3
  reg [8:0] r_word_idx;    // Palabras ya escritas: 0..256
  reg [NBIT-1:0] r_xor;    // XOR acumulado (incluido el checksum): 0 = ok
  reg [8:0] r_addr;        // Recorrido de LIMPIAR: 0..255
  reg [8:0] r_inicio;      // Primera direccion de IMEM que se llena con HALT: 0..256

  localparam [15:0] N_MAX = `DU_IMEM_DEPTH; // Mas palabras que esto no entran en la IMEM

  // N completo en el ciclo en que llega el byte alto: r_n todavia tiene solo el byte bajo,
  // asi que en LEN_HI se valida con esto y no con r_n.
  wire [15:0] w_n = {i_load_data, r_n[7:0]};

  // Palabra completa en el ciclo en que llega el 4to byte (mismo motivo que w_n). Cada byte
  // entra por arriba: despues de 4, el primero que llego queda en [7:0] (little-endian).
  wire [NBIT_32-1:0] w_word = {i_load_data, r_word};

  always @(posedge clock)
    if (i_reset)
    begin
      r_state <= IDLE;
      r_origen <= ORIG_LOAD;
      r_n <= 9'd0;
      r_word <= {(NBIT_32-NBIT){1'b0}};
      r_byte_idx <= 2'd0;
      r_word_idx <= 9'd0;
      r_xor <= {NBIT{1'b0}};
      r_addr <= 9'd0;
      r_inicio <= 9'd0;
      o_done <= 1'b0;
      o_err <= {NBIT{1'b0}};
      o_reset_done <= 1'b0;
      o_imem_we <= 1'b0;
      o_imem_addr <= {IMEM_ADDR_BITS{1'b0}};
      o_imem_wdata <= {NBIT_32{1'b0}};
      o_dmem_we <= 1'b0;
      o_dmem_addr <= {DMEM_ADDR_BITS{1'b0}};
      o_clear_used <= 1'b0;
      o_flush_all <= 1'b0;
      o_load_done <= 1'b0;
    end
    else
    begin
      // Pulsos: por defecto 0; la rama del estado los pone en 1 un ciclo
      o_done <= 1'b0;
      o_reset_done <= 1'b0;
      o_imem_we <= 1'b0;
      o_dmem_we <= 1'b0;
      o_clear_used <= 1'b0;
      o_flush_all <= 1'b0;
      o_load_done <= 1'b0;

      if (i_load_cancel)
      begin
        // Timeout o paridad: la FSM ya contesta el NACK. Va antes que el case porque puede
        // llegar en cualquier estado de la carga (incluso en LIMPIAR, si un byte extra llega
        // con la paridad mal): siempre termina con toda la IMEM en HALT (AC7).
        r_origen <= ORIG_CANCEL;
        r_inicio <= 9'd0;
        r_addr <= 9'd0;
        r_state <= LIMPIAR;
      end
      else
        case (r_state)
          IDLE:
            if (i_req_load)
            begin
              // Lo que acumula una carga arranca de cero: la anterior pudo dejarlo sucio
              r_xor <= {NBIT{1'b0}};
              r_byte_idx <= 2'd0;
              r_word_idx <= 9'd0;
              o_err <= {NBIT{1'b0}};
              r_state <= LEN_LO;
            end
            else if (i_req_reset)
            begin
              // Misma limpieza que LOAD pero sin tocar la IMEM: r_inicio no importa
              r_origen <= ORIG_RESET;
              r_addr <= 9'd0;
              r_state <= LIMPIAR;
            end

          LEN_LO:
            if (i_load_byte)
            begin
              r_n[7:0] <= i_load_data;           // LE: primero llega el byte bajo
              r_xor <= r_xor ^ i_load_data;      // el checksum incluye los bytes de N
              r_state <= LEN_HI;
            end

          LEN_HI:
            if (i_load_byte)
            begin
              r_n <= w_n[8:0];                   // si N es invalido no se usa
              r_xor <= r_xor ^ i_load_data;
              if (w_n == 16'd0 || w_n > N_MAX)
              begin
                // protocolo.md 7.1: N fuera de 1..IMEM_DEPTH -> ERR_TAMANO, IDLE e IMEM toda
                // en HALT. El resto de la carga sigue llegando: se ignora (LIMPIAR no mira
                // i_load_byte) y la FSM lo drena.
                o_err <= `DU_ERR_TAMANO;
                r_origen <= ORIG_LOAD;
                r_inicio <= 9'd0;
                r_addr <= 9'd0;
                r_state <= LIMPIAR;
              end
              else
                r_state <= PALABRAS;
            end

          PALABRAS:
            if (i_load_byte)
            begin
              r_word <= w_word[NBIT_32-1:NBIT];  // el byte mas viejo se cae por abajo
              r_xor <= r_xor ^ i_load_data;
              r_byte_idx <= r_byte_idx + 2'd1;   // 3 + 1 vuelve a 0: empieza la palabra siguiente
              if (r_byte_idx == 2'd3)
              begin
                o_imem_we <= 1'b1;
                o_imem_addr <= r_word_idx[IMEM_ADDR_BITS-1:0];
                o_imem_wdata <= w_word;
                r_word_idx <= r_word_idx + 9'd1;
                // r_word_idx todavia es el indice de esta palabra; N <= 256 entra en 9 bits
                if (r_word_idx + 9'd1 == r_n[8:0])
                  r_state <= CHECKSUM;
              end
            end

          CHECKSUM:
            if (i_load_byte)
            begin
              // r_xor ya tiene todo menos el checksum: tiene que ser igual al que mando la PC
              if (r_xor == i_load_data)
              begin
                r_inicio <= r_n[8:0];            // HALT solo despues del programa (N=256: nada)
                o_err <= {NBIT{1'b0}};
              end
              else
              begin
                r_inicio <= 9'd0;                // no se sabe que byte vino mal: toda la IMEM
                o_err <= `DU_ERR_CHECKSUM;
              end
              r_origen <= ORIG_LOAD;
              r_addr <= 9'd0;
              r_state <= LIMPIAR;
            end

          LIMPIAR:
          begin
            // Una direccion por ciclo, sin esperar nada; IMEM y DMEM en paralelo
            o_dmem_we <= 1'b1;                   // el puerto de depuracion escribe 0
            o_dmem_addr <= r_addr[DMEM_ADDR_BITS-1:0];
            if (r_origen != ORIG_RESET && r_addr >= r_inicio)
            begin
              o_imem_we <= 1'b1;
              o_imem_addr <= r_addr[IMEM_ADDR_BITS-1:0];
              o_imem_wdata <= `DU_HALT_WORD;
            end
            r_addr <= r_addr + 9'd1;
            if (r_addr == 9'd255)                // esta es la ultima direccion
              r_state <= FIN;
          end

          FIN:
          begin
            // Siempre, aun con error: despues de un error no se puede ejecutar nada igual
            o_flush_all <= 1'b1;
            o_clear_used <= 1'b1;
            o_load_done <= 1'b1;
            case (r_origen)
              ORIG_LOAD: o_done <= 1'b1;         // o_err quedo cargado en LEN_HI o CHECKSUM
              ORIG_RESET: o_reset_done <= 1'b1;
              default: ;                         // CANCEL: la FSM ya respondio el NACK
            endcase
            r_state <= IDLE;
          end
          default: r_state <= IDLE;
        endcase
    end

endmodule
