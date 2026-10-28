# Makefile del TP3: lint, simulacion y verificaciones de Python (US-102, ADR-015).
#
# Se usa desde Linux o WSL, parado en TP3/. La sintesis, implementacion y programacion
# de la placa se hacen desde la GUI de Vivado 2025.2

SHELL := /bin/bash

TB    ?=
WAVES ?= 0
HEX   ?=

TOOLS_DIR := tools
BUILD_DIR := build
TB_NAMES  := $(sort $(basename $(notdir $(shell find hw/tb -type f -name 'tb_*.v' 2>/dev/null))))
UV_RUN := cd $(TOOLS_DIR) && uv run

.PHONY: help setup lint sim sim-all test-py check-py gnu-ref check clean

help:
	@echo "Objetivos:"
	@echo "  make setup                     Instala las herramientas (Icarus, Verilator, binutils RISC-V, uv) y el entorno de Python"
	@echo "  make lint                      Lint del RTL con Verilator (falla con cualquier advertencia)"
	@echo "  make sim TB=<tb>               Simula un testbench de hw/tb con Icarus (PASS/FAIL)"
	@echo "       WAVES=1                     genera build/<tb>.vcd"
	@echo "       HEX=<ruta>                  programa a cargar con \$$readmemh (+HEX)"
	@echo "  make sim-all                   Corre todos los hw/tb/**/tb_*.v y resume el resultado"
	@echo "  make test-py                   Tests de Python con cobertura"
	@echo "  make check-py                  ruff + mypy + pytest + pip-audit"
	@echo "  make gnu-ref                   Regenera el .hex de referencia del ensamblador con GNU as (US-106)"
	@echo "  make check                     Todo: lint + sim-all + check-py (lo mismo que corre el CI)"
	@echo "  make clean                     Borra build/ y las caches de Python"

# --- Instalacion de herramientas ---------------------------------------------------------

setup:
	sudo apt-get update
	sudo apt-get install -y make iverilog verilator curl binutils-riscv64-unknown-elf
	@command -v uv > /dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
	@export PATH="$$HOME/.local/bin:$$PATH" && cd $(TOOLS_DIR) && uv sync
	@echo
	@iverilog -V | head -n 1
	@verilator --version
	@riscv64-unknown-elf-as --version | head -n 1
	@export PATH="$$HOME/.local/bin:$$PATH" && uv --version

# --- Hardware ----------------------------------------------------------------------------

lint:
	@bash hw/scripts/lint.sh

sim:
	@WAVES=$(WAVES) HEX=$(HEX) bash hw/scripts/sim.sh $(TB)

sim-all:
	@total=0; failed=0; \
	for tb in $(TB_NAMES); do \
		total=$$((total + 1)); \
		if QUIET=1 bash hw/scripts/sim.sh $$tb > /dev/null 2>&1; then \
			printf '  PASS  %s\n' $$tb; \
		else \
			failed=$$((failed + 1)); \
			printf '  FAIL  %s   (ver $(BUILD_DIR)/%s.log)\n' $$tb $$tb; \
		fi; \
	done; \
	echo; \
	echo "Testbenches: $$((total - failed)) de $$total pasaron"; \
	if [ $$total -eq 0 ]; then echo "No se encontraron testbenches en hw/tb"; exit 1; fi; \
	[ $$failed -eq 0 ]

# --- Python ------------------------------------------------------------------------------

test-py:
	@$(UV_RUN) pytest

check-py:
	@$(UV_RUN) ruff check .
	@$(UV_RUN) ruff format --check .
	@$(UV_RUN) mypy
	@$(UV_RUN) pytest
	@$(UV_RUN) pip-audit

# Referencia de GNU para test_vs_gnu.py (US-106, AC2). Se corre solo si cambia el .asm;
# el .hex se versiona para que los tests no necesiten GNU. -mno-relax: GNU resuelve los
# saltos a etiquetas locales en vez de dejarlos para el linker.
GNU_REF := $(TOOLS_DIR)/tests/assembler/fixtures/todas_las_instrucciones

gnu-ref:
	@mkdir -p $(BUILD_DIR)
	riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -mno-relax -o $(BUILD_DIR)/gnu_ref.o $(GNU_REF).asm
	riscv64-unknown-elf-objcopy -O binary -j .text $(BUILD_DIR)/gnu_ref.o $(BUILD_DIR)/gnu_ref.bin
	od -An -v -t x4 -w4 $(BUILD_DIR)/gnu_ref.bin | tr -d ' ' > $(GNU_REF).hex
	@echo "$(GNU_REF).hex: $$(wc -l < $(GNU_REF).hex) palabras"

# --- Todo --------------------------------------------------------------------------------

check: lint sim-all check-py

clean:
	rm -rf $(BUILD_DIR)
	find $(TOOLS_DIR) -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \) -prune -exec rm -rf {} +
	rm -f $(TOOLS_DIR)/.coverage
