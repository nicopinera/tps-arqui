#!/usr/bin/env bash
# Lint del RTL sintetizable con Verilator (US-102, ADR-015).
#
# Uso (desde TP3/):  hw/scripts/lint.sh
#
# Revisa cada archivo de hw/rtl (salvo legacy/) como modulo raiz; los modulos que instancia
# se buscan en las carpetas de hw/rtl. Falla si hay alguna advertencia.

set -u

mapfile -t RTL_SRCS < <(find hw/rtl -type f -name '*.v' -not -path 'hw/rtl/legacy/*' | sort)

SEARCH=()
while IFS= read -r dir; do
  SEARCH+=(-y "$dir" "-I$dir")
done < <(find hw/rtl -type d -not -path 'hw/rtl/legacy*' | sort)

FAILED=0
for src in "${RTL_SRCS[@]}"; do
  if OUTPUT="$(verilator --lint-only -Wall "${SEARCH[@]}" "$src" 2>&1)"; then
    echo "  ok     $src"
  else
    echo "  FALLA  $src"
    echo "$OUTPUT" | sed 's/^/         /'
    FAILED=$((FAILED + 1))
  fi
done

echo
if [ $FAILED -eq 0 ]; then
  echo "LINT OK (${#RTL_SRCS[@]} archivos)"
  exit 0
fi
echo "LINT FALLO: $FAILED de ${#RTL_SRCS[@]} archivos con advertencias"
exit 1
