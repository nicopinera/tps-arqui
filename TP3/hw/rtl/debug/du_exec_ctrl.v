`include "du_defs.vh"

// Control de ejecucion de la Debug Unit (US-406, US-407): RUN, STEP y ABORT.
//
// El nucleo avanza solo con i_enable (clock enable): el reloj nunca pasa por logica
// Este modulo genera ese enable desde un flip-flop y cuenta los ciclos ejecutados.
//
//   STEP  i_req_step -> o_enable = 1 durante EXACTAMENTE un ciclo -> o_step_done
//         un ciclo despues, cuando i_halted ya muestra como quedo el nucleo tras el paso.
//   RUN   i_req_run -> o_enable = 1 sostenido hasta i_halted -> o_run_fin = 1 (nivel).
//   ABORT i_req_abort durante RUN -> o_stop_fetch = 1 con o_enable = 1 (drenado: no entran
//         instrucciones nuevas y las que estan adentro terminan) hasta que los 4 latches
//         quedan con valid = 0 -> o_run_fin = 1, igual que un RUN (ADR-010).
//
// Quien decide el estado del protocolo, el motivo y el snapshot es du_cmd_fsm; aca solo se
// mueve el nucleo.
module du_exec_ctrl #(
    parameter NBIT_32 = 32
  )(
    input wire clock,
    input wire i_reset,

    // Hacia CMD_FSM
    input wire i_req_run, // Pulso: arrancar el RUN (ya se mando el ACK)
    input wire i_req_step, // Pulso: avanzar un ciclo
    input wire i_req_abort, // Pulso: ABORT (solo llega en RUN): drenar el pipeline
    output wire o_step_done, // Pulso: termino el ciclo del STEP; i_halted ya es el de despues
    output wire o_run_fin, // NIVEL: el RUN termino. Baja con el proximo i_req_run

    // Desde LOADER
    input wire i_load_done, // Pulso: fin de LOAD/RESET -> contador de ciclos a 0

    // Hacia/desde CORE
    input wire i_halted, // o_halted del nucleo: HALT o ilegal llego a WB (nivel)
    input wire [3:0] i_valid, // bits valid de los latches {MEM/WB, EX/MEM, ID/EX, IF/ID}; 0000 = pipeline vacio
    output wire o_enable, // i_enable del nucleo. Sale de un FF (ADR-001)
    output wire o_stop_fetch, // i_stop_fetch del nucleo: 1 durante el drenado de ABORT (FF)

    // Hacia DUMPER
    output wire [NBIT_32-1:0] o_ciclos // Ciclos ejecutados desde el ultimo LOAD/RESET
  );
  localparam [1:0]
             IDLE = 2'd0, // nucleo congelado, esperando pedido
             STEP = 2'd1, // el ciclo en que o_enable = 1 de un STEP
             RUN  = 2'd2, // o_enable = 1 hasta i_halted
             DRAIN = 2'd3; // ABORT: o_enable = 1 y o_stop_fetch = 1 hasta pipeline vacio

  reg [1:0] r_state;
  reg r_enable;           // -> o_enable
  reg r_stop_fetch;       // -> o_stop_fetch
  reg r_step_done;        // -> o_step_done
  reg r_run_fin;          // -> o_run_fin
  // a 100 MHz da la vuelta a 0 despues de ~43 s de RUN (posible con un lazo sin HALT, US-407); si la PC necesita distinguirlo, saturar en FFFF_FFFF.
  reg [NBIT_32-1:0] r_ciclos;

  always @(posedge clock)
  begin
    if (i_reset)
    begin
      r_state <= IDLE;
      r_enable <= 1'b0;
      r_stop_fetch <= 1'b0;
      r_step_done <= 1'b0;
      r_run_fin <= 1'b0;
      r_ciclos <= {NBIT_32{1'b0}};
    end
    else
    begin
      r_step_done<=1'b0;
      if (i_load_done)
      begin
        r_ciclos<={NBIT_32{1'b0}};
      end
      else if (r_enable && !i_halted)
      begin
        r_ciclos<= r_ciclos + {{(NBIT_32-1){1'b0}}, 1'b1};
      end
      case (r_state)
        IDLE:
          if (i_req_step)
          begin
            r_state<=STEP;
            r_enable<=1'b1;
          end
          else if (i_req_run)
          begin
            r_state<=RUN;
            r_enable<=1'b1;
            r_run_fin<=1'b0;   // nivel: se baja recien con el proximo RUN
          end
        STEP:
        begin
          r_enable<=1'b0;
          r_state<=IDLE;
          r_step_done<=1'b1;
        end
        RUN:
          // r_enable sigue en 1 un ciclo despues de i_halted; el nucleo halted lo ignora
          // i_halted primero: si llega junto con ABORT, el nucleo ya paro y no hay que drenar
          // (du_cmd_fsm igual pone ABORTED por su r_abort).
          if (i_halted)
          begin
            r_state<=IDLE;
            r_enable<=1'b0;
            r_run_fin<=1'b1;
          end
          else if (i_req_abort)
          begin
            // r_enable sigue en 1: el nucleo avanza para que salgan las instrucciones en vuelo
            r_state<=DRAIN;
            r_stop_fetch<=1'b1;
          end
        DRAIN:
          // i_halted tambien termina: un HALT que ya estaba en el pipeline llega a WB, el nucleo
          // se congela con valid de MEM/WB = 1 y los valid nunca llegarian a 0000.
          if (i_valid == 4'b0000 || i_halted)
          begin
            r_state<=IDLE;
            r_enable<=1'b0;
            r_stop_fetch<=1'b0;  // desde HALTED solo hay LOAD/RESET (flush_all): no reanuda
            r_run_fin<=1'b1;
          end
        default:
          r_state<=IDLE;
      endcase
    end
  end

  assign o_enable = r_enable;
  assign o_step_done = r_step_done;
  assign o_run_fin = r_run_fin;
  assign o_stop_fetch = r_stop_fetch;
  assign o_ciclos = r_ciclos;

endmodule
