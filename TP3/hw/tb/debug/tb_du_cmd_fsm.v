`timescale 1ns / 1ps

// Prueba de la Debug Unit de US-403 a traves de la UART, como en la placa:
//   host model -> uart_rx -> debug_unit -> uart_tx -> host model
// du_loader (US-404) es el real, adentro de debug_unit, y escribe en un core_stub.
// Los submodulos que todavia no existen los emula el testbench:
//   exec falso     STEP termina a los 3 ciclos; RUN termina cuando el test levanta
//                  r_fin_tb, o 4 ciclos despues de un ABORT
//   dumper falso   otra instancia de du_resp_tx en el canal 1 del mux: manda una trama
//                  SNAPSHOT (03) con el byte de estado como payload, o MEM_DATA (05)
//
//   AC1  PING responde PING_INFO en cualquier estado
//   AC2  STEP en IDLE responde NACK(ERR_ESTADO) y el estado no cambia
//   AC3  un byte desconocido responde NACK(ERR_DESCONOCIDO)
//   AC4  un LOAD cortado responde NACK(ERR_TIMEOUT), vuelve a IDLE y PING sigue andando
//   AC5  las respuestas de docs/protocolo.md (PING y cada NACK) salen con los bytes exactos
//   AC6  un byte con paridad mala en medio de un comando responde NACK(ERR_PARIDAD)
module tb_du_cmd_fsm;
  `include "tb_utils.vh"
  `include "du_defs.vh"

  localparam COUNT_MAX = 4;     // baud rapido: 64 ciclos por bit, ~700 ciclos por byte
  localparam TIMEOUT   = 3000;  // ~4 bytes de silencio (en la placa son 100 ms)

  reg  clock = 1'b0;
  reg  i_reset = 1'b1;
  wire host_rx;
  `include "uart_host_model.vh"

  // --- Cadena UART + Debug Unit ------------------------------------------------------------
  wire       w_s_tick, w_rx_done, w_parity_err, w_tx_start, w_tx_done;
  wire [7:0] w_rx_data, w_tx_data;
  wire [3:0] w_estado;

  wire        w_imem_we, w_dmem_we, w_clear_used, w_flush_all, w_load_done;
  wire [7:0]  w_imem_addr, w_dmem_addr;
  wire [31:0] w_imem_wdata;
  wire        w_req_run, w_req_step, w_req_abort;
  wire        w_req_dump, w_req_dump_mem;
  wire [15:0] w_dm_addr, w_dm_n;
  wire [7:0]  w_snap_estado;
  wire        w_dump_tx_start, w_dump_tx_done;
  wire [7:0]  w_dump_tx_data;

  reg        r_step_done = 1'b0;
  reg        r_fin_abort = 1'b0;    // el exec falso termino el drenado de ABORT
  reg        r_fin_tb = 1'b0;       // el test dice "el programa llego al HALT"
  reg        cfg_halted = 1'b0;     // o_halted / o_illegal del nucleo
  reg        cfg_illegal = 1'b0;
  reg        cfg_dm_err = 1'b0;     // el dumper falso responde ERR_RANGO a DUMP_MEM
  wire       w_dump_done;
  wire [7:0] w_dump_err;

  baudrate_gen #(.COUNT_MAX(COUNT_MAX)) u_baud (
    .clock(clock), .i_reset(i_reset), .o_baudrate(w_s_tick)
  );

  uart_rx u_rx (
    .clock(clock), .i_reset(i_reset), .rx(host_tx), .i_s_tick(w_s_tick),
    .o_rx_done(w_rx_done), .o_parity_err(w_parity_err), .o_dout(w_rx_data)
  );

  debug_unit #(.RX_TIMEOUT_CYCLES(TIMEOUT)) u_du (
    .clock(clock), .i_reset(i_reset),
    .i_rx_done(w_rx_done), .i_rx_data(w_rx_data), .i_parity_err(w_parity_err),
    .o_tx_start(w_tx_start), .o_tx_data(w_tx_data), .i_tx_done(w_tx_done),
    .o_imem_we(w_imem_we), .o_imem_addr(w_imem_addr), .o_imem_wdata(w_imem_wdata),
    .o_dmem_we(w_dmem_we), .o_dmem_addr(w_dmem_addr),
    .o_clear_used(w_clear_used), .o_flush_all(w_flush_all), .o_load_done(w_load_done),
    .o_req_run(w_req_run), .o_req_step(w_req_step), .o_req_abort(w_req_abort),
    .i_step_done(r_step_done), .i_run_fin(r_fin_abort || r_fin_tb),
    .i_halted(cfg_halted), .i_illegal(cfg_illegal),
    .o_req_dump(w_req_dump), .o_req_dump_mem(w_req_dump_mem),
    .o_dm_addr(w_dm_addr), .o_dm_n(w_dm_n), .o_snap_estado(w_snap_estado),
    .i_dump_done(w_dump_done), .i_dump_err(w_dump_err),
    .i_dump_tx_start(w_dump_tx_start), .i_dump_tx_data(w_dump_tx_data),
    .o_dump_tx_done(w_dump_tx_done),
    .o_estado(w_estado)
  );

  uart_tx u_tx (
    .clock(clock), .i_reset(i_reset), .i_s_tick(w_s_tick),
    .i_tx_start(w_tx_start), .i_din(w_tx_data), .o_tx(host_rx), .o_tx_done(w_tx_done)
  );

  always #5 clock = ~clock;

  // --- Nucleo falso: lo que escribe du_loader queda en su IMEM -----------------------------
  core_stub u_core (
    .clock(clock), .i_reset(i_reset), .i_enable(1'b0),
    .i_flush_all(w_flush_all), .i_stop_fetch(1'b0),
    .o_halted(), .o_illegal(), .o_pc(),
    .i_imem_we(w_imem_we), .i_imem_addr(w_imem_addr), .i_imem_wdata(w_imem_wdata),
    .i_dbg_dmem_we(w_dmem_we), .i_dbg_dmem_addr(w_dmem_addr), .i_clear_used(w_clear_used),
    .i_dbg_reg_addr(5'd0), .o_dbg_reg_data(),
    .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_used(), .o_dbg_used_count(),
    .o_stall(), .o_flush_if_id(), .o_flush_id_ex(), .o_fwd_a(), .o_fwd_b(),
    .o_if_id(), .o_id_ex(), .o_ex_mem(), .o_mem_wb()
  );

  // --- Lo que pasa entre du_cmd_fsm y du_loader (senales internas de debug_unit) -----------
  // Huerfano: la FSM reenvia un byte cuando el loader no esta recibiendo (IDLE, LIMPIAR, FIN)
  integer n_cancel = 0, n_huerfanos = 0, n_req_reset = 0;
  always @(posedge clock)
  begin
    if (u_du.w_load_cancel) n_cancel = n_cancel + 1;
    if (u_du.w_req_reset)   n_req_reset = n_req_reset + 1;
    if (u_du.w_load_byte && (u_du.u_loader.r_state == 3'd0 || u_du.u_loader.r_state >= 3'd5))
      n_huerfanos = n_huerfanos + 1;
  end

  // --- Exec falso (du_exec_ctrl) -------------------------------------------------------------
  integer step_cnt = 0, abort_cnt = 0;
  integer n_req_run = 0;
  always @(posedge clock)
  begin
    r_step_done  <= 1'b0;
    if (w_req_step)
      step_cnt = 3;
    else if (step_cnt > 0)
    begin
      step_cnt = step_cnt - 1;
      if (step_cnt == 0)
        r_step_done <= 1'b1;
    end
    if (w_req_run)
    begin
      r_fin_abort <= 1'b0;             // contrato: i_run_fin baja con o_req_run
      n_req_run = n_req_run + 1;
    end
    if (w_req_abort)
      abort_cnt = 4;                   // drenado del pipeline
    else if (abort_cnt > 0)
    begin
      abort_cnt = abort_cnt - 1;
      if (abort_cnt == 0)
        r_fin_abort <= 1'b1;
    end
  end

  // --- Dumper falso (du_dumper, US-405): trama corta por el canal 1 ----------------------------
  reg        r_dp_send = 1'b0, r_dp_err = 1'b0;
  reg  [7:0] r_dp_tipo = 8'h00, r_dp_cod = 8'h00;
  wire       w_dp_done;
  reg [15:0] dm_addr_cap, dm_n_cap;
  integer    n_dump = 0;

  du_resp_tx u_dump (
    .clock(clock), .i_reset(i_reset),
    .i_send(r_dp_send), .i_tipo(r_dp_tipo), .i_codigo(r_dp_cod), .o_done(w_dp_done),
    .o_tx_start(w_dump_tx_start), .o_tx_data(w_dump_tx_data), .i_tx_done(w_dump_tx_done)
  );

  assign w_dump_done = w_dp_done || r_dp_err;
  assign w_dump_err  = r_dp_err ? `DU_ERR_RANGO : 8'h00;

  always @(posedge clock)
  begin
    r_dp_send <= 1'b0;
    r_dp_err  <= 1'b0;
    if (w_req_dump)
    begin
      r_dp_send <= 1'b1;
      r_dp_tipo <= `DU_TIPO_SNAPSHOT;
      r_dp_cod  <= w_snap_estado;      // el byte 0 del snapshot real
      n_dump = n_dump + 1;
    end
    if (w_req_dump_mem)
    begin
      dm_addr_cap = w_dm_addr;
      dm_n_cap    = w_dm_n;
      if (cfg_dm_err)
        r_dp_err <= 1'b1;              // valida el rango y no manda nada
      else
      begin
        r_dp_send <= 1'b1;
        r_dp_tipo <= `DU_TIPO_MEM_DATA;
        r_dp_cod  <= w_dm_n[7:0];
      end
    end
  end

  // --- Tareas del host ---------------------------------------------------------------------
  reg r_ok;

  // Manda cmd + n_args bytes de host_args y recibe la respuesta. recv_frame arranca durante
  // el ultimo byte: la respuesta empieza antes de que send_cmd termine el bit de stop, y si
  // arrancara al principio su timeout de 100 bits no alcanzaria para cargas largas.
  task enviar;
    input [7:0]   cmd;
    input integer n_args;
    begin
      fork
        send_cmd(cmd, n_args);
        begin
          repeat (n_args * 11 * host_ciclos_bit) @(negedge clock);
          recv_frame(r_ok);
        end
      join
    end
  endtask

  // La respuesta tiene que ser tipo/len/payload y el estado despues, `estado`
  task verificar;
    input [8*24-1:0] nombre;
    input [7:0]      tipo;
    input integer    len;
    input [7:0]      payload;
    input [3:0]      estado;
    begin
      check_eq(nombre, {31'd0, r_ok}, 32'd1);
      check_eq(nombre, {24'd0, host_tipo}, {24'd0, tipo});
      check_eq(nombre, {16'd0, host_len}, len);
      if (len == 1)
        check_eq(nombre, {24'd0, host_payload[0]}, {24'd0, payload});
      repeat (3 * host_ciclos_bit) @(negedge clock);   // que termine de salir la trama
      check_eq(nombre, {28'd0, w_estado}, {28'd0, estado});
    end
  endtask

  task nack_estado;               // comando valido que no vale en este estado
    input [7:0] cmd;
    input [3:0] estado;
    begin
      enviar(cmd, 0);
      verificar("NACK(ERR_ESTADO)", `DU_TIPO_NACK, 1, `DU_ERR_ESTADO, estado);
    end
  endtask

  task ping;                      // AC1 en cualquier estado
    input [3:0] estado;
    begin
      enviar(`DU_CMD_PING, 0);
      verificar("PING", `DU_TIPO_PING_INFO, 1, `DU_PROTO_VERSION, estado);
    end
  endtask

  task dump;                      // DUMP manda el snapshot y vuelve al mismo estado
    input [7:0] snap;
    input [3:0] estado;
    begin
      enviar(`DU_CMD_DUMP, 0);
      verificar("DUMP", `DU_TIPO_SNAPSHOT, 1, snap, estado);
    end
  endtask

  // LOAD de una palabra: N = 1 (2 B) + palabra (4 B) + checksum (1 B)
  task armar_load;
    input [31:0] palabra;
    input        checksum_malo;
    begin
      host_args[0] = 8'h01;
      host_args[1] = 8'h00;
      host_args[2] = palabra[7:0];
      host_args[3] = palabra[15:8];
      host_args[4] = palabra[23:16];
      host_args[5] = palabra[31:24];
      host_args[6] = host_args[0] ^ host_args[1] ^ host_args[2] ^ host_args[3] ^
                     host_args[4] ^ host_args[5] ^ {7'd0, checksum_malo};
    end
  endtask

  task cargar;                    // LOAD correcto: termina en READY
    begin
      armar_load(32'h00500093, 1'b0);
      enviar(`DU_CMD_LOAD, 7);
      verificar("LOAD ok", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_READY);
    end
  endtask

  task correr;                    // RUN: ACK inmediato y queda en RUN
    begin
      enviar(`DU_CMD_RUN, 0);
      verificar("RUN: ACK", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_RUN);
    end
  endtask

  task dump_mem;
    input [15:0] addr;
    input [15:0] n;
    begin
      host_args[0] = addr[7:0];
      host_args[1] = addr[15:8];
      host_args[2] = n[7:0];
      host_args[3] = n[15:8];
      enviar(`DU_CMD_DUMP_MEM, 4);
    end
  endtask

  integer b, errores_antes, aux;

  initial
  begin
    tb_init;
    host_ciclos_bit = 16 * COUNT_MAX;

    repeat (4) @(negedge clock);
    i_reset = 1'b0;
    repeat (4) @(negedge clock);
    check_eq("arranca en IDLE", {28'd0, w_estado}, {28'd0, `DU_ESTADO_IDLE});

    // === IDLE ==========================================================================
    ping(`DU_ESTADO_IDLE);                                            // AC1, AC5
    nack_estado(`DU_CMD_STEP, `DU_ESTADO_IDLE);                       // AC2
    nack_estado(`DU_CMD_RUN, `DU_ESTADO_IDLE);
    nack_estado(`DU_CMD_ABORT, `DU_ESTADO_IDLE);
    enviar(8'h5A, 0);                                                 // AC3 ('Z')
    verificar("byte desconocido", `DU_TIPO_NACK, 1, `DU_ERR_DESCONOCIDO, `DU_ESTADO_IDLE);
    dump(8'h00, `DU_ESTADO_IDLE);
    enviar(`DU_CMD_RESET, 0);                                         // sin programa
    verificar("RESET en IDLE", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_IDLE);
    check_eq("RESET en IDLE pide la limpieza", n_req_reset, 1);

    // Paridad mala en el byte de comando: NACK enseguida, sin cambio (AC6, AC5)
    fork
      send_byte_paridad(`DU_CMD_PING, ~^`DU_CMD_PING);
      recv_frame(r_ok);
    join
    verificar("paridad en comando", `DU_TIPO_NACK, 1, `DU_ERR_PARIDAD, `DU_ESTADO_IDLE);

    // Los 248 bytes que no son comandos responden ERR_DESCONOCIDO (resumen en un chequeo)
    errores_antes = tb_errors;
    for (b = 0; b < 256; b = b + 1)
      case (b[7:0])
        `DU_CMD_LOAD, `DU_CMD_RUN, `DU_CMD_STEP, `DU_CMD_DUMP, `DU_CMD_RESET,
        `DU_CMD_ABORT, `DU_CMD_PING, `DU_CMD_DUMP_MEM: ;
        default:
        begin
          enviar(b[7:0], 0);
          if (!r_ok || host_tipo !== `DU_TIPO_NACK || host_payload[0] !== `DU_ERR_DESCONOCIDO)
          begin
            tb_errors = tb_errors + 1;
            $display("  [FALLA] byte 0x%02h: tipo %02h payload %02h", b[7:0], host_tipo,
                     host_payload[0]);
          end
        end
      endcase
    check_eq("248 bytes desconocidos", tb_errors - errores_antes, 0);

    // === LOAD con errores =================================================================
    // AC4: LOAD cortado despues de N y media palabra -> NACK(ERR_TIMEOUT), IDLE, PING anda
    armar_load(32'h00500093, 1'b0);
    enviar(`DU_CMD_LOAD, 4);
    verificar("LOAD cortado: timeout", `DU_TIPO_NACK, 1, `DU_ERR_TIMEOUT, `DU_ESTADO_IDLE);
    check_eq("LOAD cortado: cancela la carga", n_cancel, 1);
    check_eq("LOAD cortado: IMEM con HALT", u_core.r_imem[0], `DU_HALT_WORD);   // US-404 AC7
    ping(`DU_ESTADO_IDLE);

    // Checksum incorrecto: lo detecta el loader, NACK(ERR_CHECKSUM) y a IDLE
    armar_load(32'h00500093, 1'b1);
    enviar(`DU_CMD_LOAD, 7);
    verificar("LOAD checksum", `DU_TIPO_NACK, 1, `DU_ERR_CHECKSUM, `DU_ESTADO_IDLE);

    // N = 0 con bytes de mas (uno es 3F = PING): el loader corta despues de N, la FSM drena
    // y responde un solo NACK(ERR_TAMANO); los bytes de mas no se interpretan (seccion 7.2)
    host_args[0] = 8'h00;
    host_args[1] = 8'h00;
    host_args[2] = `DU_CMD_PING;
    host_args[3] = `DU_CMD_STEP;
    host_args[4] = 8'h11;
    enviar(`DU_CMD_LOAD, 5);
    verificar("LOAD N=0: drena", `DU_TIPO_NACK, 1, `DU_ERR_TAMANO, `DU_ESTADO_IDLE);
    recv_frame(r_ok);
    check_eq("LOAD N=0: una sola respuesta", {31'd0, r_ok}, 32'd0);
    check_eq("bytes drenados no van al loader", n_huerfanos, 0);

    // AC6: paridad mala en la primera palabra -> drena, NACK(ERR_PARIDAD), IDLE, sigue andando
    armar_load(32'h00500093, 1'b0);
    host_paridad_mala_en = 3;
    enviar(`DU_CMD_LOAD, 7);
    host_paridad_mala_en = -1;
    verificar("LOAD paridad: drena", `DU_TIPO_NACK, 1, `DU_ERR_PARIDAD, `DU_ESTADO_IDLE);
    check_eq("LOAD paridad: cancela la carga", n_cancel, 2);
    ping(`DU_ESTADO_IDLE);

    // === LOAD correcto -> READY ==========================================================
    cargar;
    check_eq("LOAD: palabra en IMEM[0]", u_core.r_imem[0], 32'h00500093);
    check_eq("LOAD: HALT en IMEM[1]", u_core.r_imem[1], `DU_HALT_WORD);
    ping(`DU_ESTADO_READY);
    nack_estado(`DU_CMD_ABORT, `DU_ESTADO_READY);
    dump(8'h02, `DU_ESTADO_READY);

    // DUMP_MEM: argumentos, MEM_DATA y vuelta al estado previo
    dump_mem(16'h0000, 16'h0002);
    verificar("DUMP_MEM", `DU_TIPO_MEM_DATA, 1, 8'h02, `DU_ESTADO_READY);
    check_eq("DUMP_MEM: direccion", {16'd0, dm_addr_cap}, 32'h0000);
    check_eq("DUMP_MEM: cantidad", {16'd0, dm_n_cap}, 32'h0002);
    cfg_dm_err = 1'b1;
    dump_mem(16'h03FC, 16'h0002);
    cfg_dm_err = 1'b0;
    verificar("DUMP_MEM fuera de rango", `DU_TIPO_NACK, 1, `DU_ERR_RANGO, `DU_ESTADO_READY);
    check_eq("DUMP_MEM: direccion 0x3FC", {16'd0, dm_addr_cap}, 32'h03FC);
    host_args[0] = 8'h00;                                     // cortado despues de 1 byte
    enviar(`DU_CMD_DUMP_MEM, 1);
    verificar("DUMP_MEM cortado", `DU_TIPO_NACK, 1, `DU_ERR_TIMEOUT, `DU_ESTADO_READY);
    host_args[0] = 8'h00; host_args[1] = 8'h00; host_args[2] = 8'h02; host_args[3] = 8'h00;
    host_paridad_mala_en = 2;
    enviar(`DU_CMD_DUMP_MEM, 4);
    host_paridad_mala_en = -1;
    verificar("DUMP_MEM paridad", `DU_TIPO_NACK, 1, `DU_ERR_PARIDAD, `DU_ESTADO_READY);

    // === STEP -> STEPPING -> HALTED =========================================================
    enviar(`DU_CMD_STEP, 0);
    verificar("STEP", `DU_TIPO_SNAPSHOT, 1, 8'h04, `DU_ESTADO_STEPPING);
    ping(`DU_ESTADO_STEPPING);
    nack_estado(`DU_CMD_ABORT, `DU_ESTADO_STEPPING);
    dump(8'h04, `DU_ESTADO_STEPPING);
    cfg_halted = 1'b1;                                        // en este ciclo llega el HALT
    enviar(`DU_CMD_STEP, 0);
    verificar("STEP que termina", `DU_TIPO_SNAPSHOT, 1, 8'h16, `DU_ESTADO_HALTED);
    cfg_halted = 1'b0;

    // === HALTED ================================================================================
    ping(`DU_ESTADO_HALTED);
    nack_estado(`DU_CMD_STEP, `DU_ESTADO_HALTED);
    nack_estado(`DU_CMD_RUN, `DU_ESTADO_HALTED);
    nack_estado(`DU_CMD_ABORT, `DU_ESTADO_HALTED);
    dump(8'h16, `DU_ESTADO_HALTED);                           // el motivo se conserva
    enviar(`DU_CMD_RESET, 0);
    verificar("RESET en HALTED", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_READY);
    dump(8'h02, `DU_ESTADO_READY);                            // RESET borra el motivo

    // === RUN ================================================================================
    aux = n_req_run;
    correr;
    check_eq("RUN pide la ejecucion despues del ACK", n_req_run - aux, 1);
    ping(`DU_ESTADO_RUN);
    nack_estado(`DU_CMD_LOAD, `DU_ESTADO_RUN);
    nack_estado(`DU_CMD_RESET, `DU_ESTADO_RUN);
    nack_estado(`DU_CMD_RUN, `DU_ESTADO_RUN);
    nack_estado(`DU_CMD_STEP, `DU_ESTADO_RUN);
    nack_estado(`DU_CMD_DUMP, `DU_ESTADO_RUN);
    nack_estado(`DU_CMD_DUMP_MEM, `DU_ESTADO_RUN);
    enviar(8'h5A, 0);
    verificar("desconocido en RUN", `DU_TIPO_NACK, 1, `DU_ERR_DESCONOCIDO, `DU_ESTADO_RUN);
    fork                                                      // paridad: el RUN sigue
      send_byte_paridad(`DU_CMD_PING, ~^`DU_CMD_PING);
      recv_frame(r_ok);
    join
    verificar("paridad en RUN", `DU_TIPO_NACK, 1, `DU_ERR_PARIDAD, `DU_ESTADO_RUN);

    // El programa termina por instruccion ilegal -> snapshot con motivo ILLEGAL
    cfg_halted  = 1'b1;
    cfg_illegal = 1'b1;
    fork
      recv_frame(r_ok);
      begin
        repeat (10) @(negedge clock);
        r_fin_tb = 1'b1;
      end
    join
    verificar("RUN -> ILLEGAL", `DU_TIPO_SNAPSHOT, 1, 8'h26, `DU_ESTADO_HALTED);
    r_fin_tb    = 1'b0;
    cfg_halted  = 1'b0;
    cfg_illegal = 1'b0;

    // El fin del RUN llega mientras sale un PING_INFO: no se pierde (i_run_fin es un nivel)
    enviar(`DU_CMD_RESET, 0);
    verificar("RESET", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_READY);
    correr;
    cfg_halted = 1'b1;
    fork
      send_byte(`DU_CMD_PING);
      begin
        recv_frame(r_ok);
        check_eq("fin durante PING: PING_INFO", {24'd0, host_tipo}, {24'd0, `DU_TIPO_PING_INFO});
        recv_frame(r_ok);
      end
      begin
        repeat (11 * host_ciclos_bit + 1000) @(negedge clock);  // con la respuesta saliendo
        r_fin_tb = 1'b1;
      end
    join
    verificar("fin durante PING: snapshot", `DU_TIPO_SNAPSHOT, 1, 8'h16, `DU_ESTADO_HALTED);
    r_fin_tb   = 1'b0;
    cfg_halted = 1'b0;

    // ABORT: sin respuesta inmediata; despues del drenado, snapshot con motivo ABORTED
    enviar(`DU_CMD_RESET, 0);
    verificar("RESET", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_READY);
    correr;
    enviar(`DU_CMD_ABORT, 0);
    verificar("ABORT", `DU_TIPO_SNAPSHOT, 1, 8'h36, `DU_ESTADO_HALTED);

    // Otro RUN despues del ABORT: el i_run_fin viejo no lo termina en el primer ciclo
    enviar(`DU_CMD_RESET, 0);
    verificar("RESET", `DU_TIPO_ACK, 0, 8'h00, `DU_ESTADO_READY);
    correr;
    repeat (50) @(negedge clock);
    check_eq("RUN tras ABORT sigue corriendo", {28'd0, w_estado}, {28'd0, `DU_ESTADO_RUN});
    enviar(`DU_CMD_ABORT, 0);
    verificar("ABORT", `DU_TIPO_SNAPSHOT, 1, 8'h36, `DU_ESTADO_HALTED);

    // LOAD desde HALTED borra el motivo y vuelve a READY
    cargar;
    dump(8'h02, `DU_ESTADO_READY);
    check_eq("bytes huerfanos al final", n_huerfanos, 0);

    tb_finish;
  end
endmodule
