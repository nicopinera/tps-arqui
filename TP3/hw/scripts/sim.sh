#!/usr/bin/env bash
# Compila y corre un testbench con Icarus Verilog y decide PASS/FAIL (US-102, ADR-015).
#
# Uso (desde TP3/):  hw/scripts/sim.sh <tb_nombre>
# Variables de entorno opcionales:
#   WAVES=1      genera build/<tb_nombre>.vcd
#   HEX=<ruta>   pasa +HEX=<ruta> al testbench (programa a cargar con $readmemh)
#   QUIET=1      no muestra la salida de la simulacion (la deja en build/<tb_nombre>.log)
#
# Codigo de salida: 0 = TEST PASSED, 1 = TEST FAILED o sin veredicto, 2 = error de uso o de compilacion.

set -u

TB="${1:-}"
BUILD_DIR="build"

if [ -z "$TB" ]; then
  echo "Uso: make sim TB=<tb_nombre>   (por ejemplo TB=tb_uart_loopback)" >&2
  exit 2
fi

TB_FILE="$(find hw/tb -type f -name "${TB}.v" | head -n 1)"
if [ -z "$TB_FILE" ]; then
  echo "No se encontro hw/tb/**/${TB}.v" >&2
  exit 2
fi

# RTL sintetizable (todo hw/rtl salvo legacy/) y modulos auxiliares de hw/tb que no son testbenches
mapfile -t RTL_SRCS < <(find hw/rtl -type f -name '*.v' -not -path 'hw/rtl/legacy/*' | sort)
mapfile -t TB_HELPERS < <(find hw/tb -type f -name '*.v' -not -name 'tb_*.v' | sort)

# Carpetas de include: hw/tb/common, la del testbench y las del RTL (para los .vh)
INCLUDES=(-I hw/tb/common -I "$(dirname "$TB_FILE")")
while IFS= read -r dir; do
  INCLUDES+=(-I "$dir")
done < <(find hw/rtl -type d -not -path 'hw/rtl/legacy*' | sort)

mkdir -p "$BUILD_DIR"
VVP_FILE="$BUILD_DIR/$TB.vvp"
LOG_FILE="$BUILD_DIR/$TB.log"

if ! iverilog -g2001 -Wall -Wno-timescale "${INCLUDES[@]}" -s "$TB" -o "$VVP_FILE" \
    "${RTL_SRCS[@]}" "${TB_HELPERS[@]}" "$TB_FILE" > "$LOG_FILE" 2>&1; then
  cat "$LOG_FILE"
  echo "ERROR DE COMPILACION: $TB"
  exit 2
fi

PLUSARGS=()
if [ "${WAVES:-0}" = "1" ]; then
  PLUSARGS+=("+WAVES=$BUILD_DIR/$TB.vcd")
fi
if [ -n "${HEX:-}" ]; then
  PLUSARGS+=("+HEX=$HEX")
fi

vvp -n "$VVP_FILE" "${PLUSARGS[@]}" >> "$LOG_FILE" 2>&1
VVP_STATUS=$?

if [ "${QUIET:-0}" != "1" ]; then
  cat "$LOG_FILE"
fi

if [ $VVP_STATUS -eq 0 ] && grep -q "TEST PASSED" "$LOG_FILE" && ! grep -q "TEST FAILED" "$LOG_FILE"; then
  exit 0
fi

if ! grep -q "TEST FAILED" "$LOG_FILE"; then
  echo "SIN VEREDICTO: $TB no imprimio TEST PASSED ni TEST FAILED (ver $LOG_FILE)"
fi
exit 1
