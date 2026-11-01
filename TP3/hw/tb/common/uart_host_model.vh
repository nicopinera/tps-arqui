// Modelo de la PC para los testbenches de la pista B (US-402): habla UART 8E1 por dos
// lineas, igual que el puente USB-UART de la placa, pero desde dentro de la simulacion.
//
// Se incluye DENTRO del modulo del testbench, despues de tb_utils.vh y de declarar:
//
//   reg  clock;        reloj del testbench
//   wire host_rx;      linea FPGA -> PC: conectarla al tx del DUT
//
// El modelo declara:
//
//   host_tx            linea PC -> FPGA (reposo en 1): conectarla al rx del DUT
//   host_ciclos_bit    ciclos de reloj por bit = N_TICK * COUNT_MAX del DUT.
//                      El testbench la carga al principio, antes de usar las tareas.
//
// Tareas:
//   send_byte(dato)                    trama 8E1 correcta
//   send_byte_paridad(dato, paridad)   trama con el bit de paridad que se pase (inyectar errores)
//   recv_byte(dato, ok)                espera una trama en host_rx; ok = 0 si no llega en
//                                      HOST_ESPERA_BITS tiempos de bit, o si la paridad o el
//                                      stop vienen mal
//   send_cmd(cmd, n_args)              manda `cmd` y los primeros n_args bytes de host_args.
//                                      Con menos argumentos de los que el comando espera, la
//                                      trama queda truncada. host_paridad_mala_en = i invierte
//                                      la paridad del byte i (0 = el codigo de comando).
//   recv_frame(ok)                     recibe [A5][tipo][long LE][payload][XOR] y deja
//                                      host_tipo, host_len y host_payload; ok = 0 si falta un
//                                      byte, no empieza con A5 o el checksum no coincide.
//
// Verilog 2001 no deja pasar ni devolver arreglos en una task: los argumentos y el payload
// viajan en los arreglos del modelo (host_args, host_payload).

localparam HOST_ESPERA_BITS = 100;   // ~9 tramas de silencio antes de dar timeout
localparam HOST_MAX_ARGS    = 1100;  // LOAD de 256 palabras: 2 + 1024 + 1 bytes
localparam HOST_MAX_PAYLOAD = 2048;  // snapshot completo: 221 + 6 * 256 = 1757 bytes

reg     host_tx = 1'b1;
integer host_ciclos_bit = 0;

reg [7:0] host_args [0:HOST_MAX_ARGS-1];
integer   host_paridad_mala_en = -1;

reg [7:0]  host_tipo;
reg [15:0] host_len;
reg [7:0]  host_payload [0:HOST_MAX_PAYLOAD-1];

// Manda una trama start + 8 datos (LSB primero) + paridad + stop, un bit cada host_ciclos_bit.
task send_byte_paridad;
  input [7:0] dato;
  input       paridad;
  integer i;
  begin
    if (host_ciclos_bit <= 0)
      tb_timeout("host_ciclos_bit sin cargar");
    host_tx = 1'b0;                                   // start
    repeat (host_ciclos_bit) @(negedge clock);
    for (i = 0; i < 8; i = i + 1)
    begin
      host_tx = dato[i];
      repeat (host_ciclos_bit) @(negedge clock);
    end
    host_tx = paridad;
    repeat (host_ciclos_bit) @(negedge clock);
    host_tx = 1'b1;                                   // stop
    repeat (host_ciclos_bit) @(negedge clock);
  end
endtask

task send_byte;
  input [7:0] dato;
  begin
    send_byte_paridad(dato, ^dato);                   // paridad par: total de unos par
  end
endtask

// Espera el flanco de bajada del start y muestrea cada bit en su centro, como un receptor real.
task recv_byte;
  output [7:0] dato;
  output       ok;
  integer i, espera;
  reg paridad;
  begin
    dato = 8'h00;
    ok   = 1'b0;
    espera = 0;
    while (host_rx && espera < HOST_ESPERA_BITS * host_ciclos_bit)
    begin
      @(negedge clock);
      espera = espera + 1;
    end
    if (host_rx)
      $display("  [host] timeout esperando un byte (t = %0t)", $time);
    else
    begin
      repeat (host_ciclos_bit + host_ciclos_bit / 2) @(negedge clock);  // centro de d0
      for (i = 0; i < 8; i = i + 1)
      begin
        dato[i] = host_rx;
        repeat (host_ciclos_bit) @(negedge clock);
      end
      paridad = host_rx;
      repeat (host_ciclos_bit) @(negedge clock);                       // centro del stop
      ok = (paridad == ^dato) && host_rx;
      if (!ok)
        $display("  [host] byte 0x%02h con paridad o stop erroneos (t = %0t)", dato, $time);
    end
  end
endtask

// Codigo de comando + argumentos de host_args, con la paridad mala opcional en un byte.
task send_cmd;
  input [7:0] cmd;
  input integer n_args;
  integer i;
  begin
    send_byte_paridad(cmd, (host_paridad_mala_en == 0) ? ~^cmd : ^cmd);
    for (i = 0; i < n_args; i = i + 1)
      send_byte_paridad(host_args[i],
                        (host_paridad_mala_en == i + 1) ? ~^host_args[i] : ^host_args[i]);
  end
endtask

// Trama FPGA -> PC (docs/protocolo.md, seccion 6). El A5 no entra en el checksum.
task recv_frame;
  output ok;
  reg [7:0] b, xor_calc;
  reg       b_ok;
  integer   i;
  begin
    ok = 1'b0;
    host_tipo = 8'h00;
    host_len  = 16'h0000;
    recv_byte(b, b_ok);
    if (!b_ok || b !== 8'hA5)
      $display("  [host] la trama no empieza con A5 (llego 0x%02h, t = %0t)", b, $time);
    else
    begin
      ok = 1'b1;
      recv_byte(host_tipo, b_ok);     ok = ok && b_ok;
      recv_byte(host_len[7:0], b_ok); ok = ok && b_ok;  // longitud little-endian
      recv_byte(host_len[15:8], b_ok); ok = ok && b_ok;
      xor_calc = host_tipo ^ host_len[7:0] ^ host_len[15:8];
      if (host_len > HOST_MAX_PAYLOAD)
      begin
        $display("  [host] longitud %0d mayor que el buffer (t = %0t)", host_len, $time);
        ok = 1'b0;
      end
      for (i = 0; ok && i < host_len; i = i + 1)
      begin
        recv_byte(host_payload[i], b_ok);
        ok = ok && b_ok;
        xor_calc = xor_calc ^ host_payload[i];
      end
      if (ok)
      begin
        recv_byte(b, b_ok);
        ok = b_ok && (b === xor_calc);
        if (b_ok && b !== xor_calc)
          $display("  [host] checksum 0x%02h, esperado 0x%02h (t = %0t)", b, xor_calc, $time);
      end
    end
  end
endtask
