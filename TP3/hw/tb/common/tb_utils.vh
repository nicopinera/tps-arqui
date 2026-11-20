// Utilidades comunes de los testbenches (US-102, ADR-015).
//
// Se incluye DENTRO del modulo del testbench:
//
//   module tb_algo;
//     `include "tb_utils.vh"
//     ...
//     initial begin
//       tb_init;
//       check_eq("resultado", {24'd0, w_dato}, 32'h0000_00A5);
//       tb_finish;
//     end
//   endmodule
//
// Opciones al ejecutar (plusargs):
//   +WAVES=<archivo.vcd>   vuelca las ondas del testbench en ese archivo

integer tb_errors;
integer tb_checks;
reg [1023:0] tb_waves_file;

initial
begin
  tb_errors = 0;
  tb_checks = 0;
end

// Activa el volcado de ondas si se paso +WAVES=<archivo>. Llamar al principio del test.
task tb_init;
  begin
    if ($value$plusargs("WAVES=%s", tb_waves_file))
    begin
      $dumpfile(tb_waves_file);
      $dumpvars(0);
    end
  end
endtask

// Compara dos valores de hasta 32 bits; si difieren, cuenta un error y muestra el detalle.
task check_eq;
  input [255:0] nombre;   // hasta 32 caracteres
  input [31:0]  obtenido;
  input [31:0]  esperado;
  begin
    tb_checks = tb_checks + 1;
    if (obtenido !== esperado)
    begin
      tb_errors = tb_errors + 1;
      $display("  [FALLA] %0s: obtenido = 0x%08h, esperado = 0x%08h (t = %0t)",
               nombre, obtenido, esperado, $time);
    end
  end
endtask

// Imprime el veredicto y termina la simulacion.
task tb_finish;
  begin
    if (tb_errors == 0)
      $display("TEST PASSED (%0d chequeos)", tb_checks);
    else
      $display("TEST FAILED (%0d errores)", tb_errors);
    $finish(0);
  end
endtask

// Corta el test con falla si se supera el limite de ciclos (evita simulaciones colgadas).
task tb_timeout;
  input [255:0] motivo;
  begin
    tb_errors = tb_errors + 1;
    $display("  [FALLA] timeout: %0s (t = %0t)", motivo, $time);
    tb_finish;
  end
endtask
