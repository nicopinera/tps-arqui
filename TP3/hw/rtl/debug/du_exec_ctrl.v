`include "du_defs.vh"

// Control de ejecucion de la Debug Unit (US-406): RUN y STEP.
//
// El nucleo avanza solo con i_enable (clock enable): el reloj nunca pasa por logica
// Este modulo genera ese enable desde un flip-flop y cuenta los ciclos ejecutados.
//
//   STEP  i_req_step -> o_enable = 1 durante EXACTAMENTE un ciclo -> o_step_done
//         un ciclo despues, cuando i_halted ya muestra como quedo el nucleo tras el paso.
//   RUN   i_req_run -> o_enable = 1 sostenido hasta i_halted -> o_run_fin = 1 (nivel).
//
// Quien decide el estado del protocolo, el motivo y el snapshot es du_cmd_fsm; aca solo se
// mueve el nucleo. ABORT (i_req_abort, o_stop_fetch) es de US-407.
module du_exec_ctrl #(
    parameter NBIT_32 = 32
  )(
    input wire clock,
    input wire i_reset,

    // Hacia CMD_FSM
    input wire i_req_run, // Pulso: arrancar el RUN (ya se mando el ACK)
    input wire i_req_step, // Pulso: avanzar un ciclo
    input wire i_req_abort, // Pulso: ABORT. TODO(US-407): drenar el pipeline con o_stop_fetch
    output wire o_step_done, // Pulso: termino el ciclo del STEP; i_halted ya es el de despues
    output wire o_run_fin, // NIVEL: el RUN termino. Baja con el proximo i_req_run

    // Desde LOADER
    input wire i_load_done, // Pulso: fin de LOAD/RESET -> contador de ciclos a 0

    // Hacia/desde CORE
    input wire i_halted, // o_halted del nucleo: HALT o ilegal llego a WB (nivel)
    output wire o_enable, // i_enable del nucleo. Sale de un FF (ADR-001)
    output wire o_stop_fetch, // i_stop_fetch del nucleo. TODO(US-407): por ahora siempre 0

    // Hacia DUMPER
    output wire [NBIT_32-1:0] o_ciclos // Ciclos ejecutados desde el ultimo LOAD/RESET
  );
  localparam [1:0]
             IDLE = 2'd0, // nucleo congelado, esperando pedido
             STEP = 2'd1, // el ciclo en que o_enable = 1 de un STEP
             RUN  = 2'd2; // o_enable = 1 hasta i_halted

  reg [1:0] r_state;
  reg r_enable;           // -> o_enable
  reg r_step_done;        // -> o_step_done
  reg r_run_fin;          // -> o_run_fin
  // a 100 MHz da la vuelta a 0 despues de ~43 s de RUN (posible con un lazo sin HALT, US-407); si la PC necesita distinguirlo, saturar en FFFF_FFFF.
  reg [NBIT_32-1:0] r_ciclos;

  // TODO(US-407): se usa para el drenado de ABORT
  /* verilator lint_off UNUSEDSIGNAL */
  wire w_abort_sin_uso = i_req_abort;
  /* verilator lint_on UNUSEDSIGNAL */

  always @(posedge clock)
  begin
    if (i_reset)
    begin
      r_state <= IDLE;
      r_enable <= 1'b0;
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
          // TODO(US-407): ABORT tambien termina el RUN (despues del drenado)
          if (i_halted)
          begin
            r_state<=IDLE;
            r_enable<=1'b0;
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
  assign o_stop_fetch = 1'b0;
  assign o_ciclos = r_ciclos;

endmodule
