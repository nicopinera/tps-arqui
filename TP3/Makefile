# Makefile del TP3: lint, simulacion y verificaciones de Python (US-102, ADR-015).
#
# Se usa desde Linux o WSL, parado en TP3/. La sintesis, implementacion y programacion
# de la placa se hacen desde la GUI de Vivado 2025.2; synth-ooc usa Vivado en modo batch.

SHELL := /bin/bash

TB    ?=
WAVES ?= 0
HEX   ?=
EXPECTED ?=
ARGS  ?=
MOD   ?=
VIVADO ?= vivado

TOOLS_DIR := tools
BUILD_DIR := build
# tb_core_programs necesita un programa: lo corre sim-programs, no sim-all
TB_NAMES  := $(filter-out tb_core_programs,$(sort $(basename $(notdir $(shell find hw/tb -type f -name 'tb_*.v' 2>/dev/null)))))
# Programas que corre sim-programs, como <carpeta>/<nombre> relativo a asm/tests
PROG_DIRS := h2 hazards instr
PROGRAMS  := $(sort $(patsubst asm/tests/%.asm,%,$(foreach d,$(PROG_DIRS),$(wildcard asm/tests/$(d)/*.asm))))
UV_RUN := cd $(TOOLS_DIR) && uv run

.PHONY: help setup lint sim sim-all sim-programs verify synth-ooc timing-core test-py check-py gnu-ref check clean

help:
	@echo "Objetivos:"
	@echo "  make setup                     Instala las herramientas (Icarus, Verilator, binutils RISC-V, uv) y el entorno de Python"
	@echo "  make lint                      Lint del RTL con Verilator (falla con cualquier advertencia)"
	@echo "  make sim TB=<tb>               Simula un testbench de hw/tb con Icarus (PASS/FAIL)"
	@echo "       WAVES=1                     genera build/<tb>.vcd"
	@echo "       HEX=<ruta>                  programa a cargar con \$$readmemh (+HEX)"
	@echo "       EXPECTED=<ruta>             estado final del golden model (+EXPECTED)"
	@echo "       ARGS=\"+X +Y=1\"              plusargs extra"
	@echo "  make sim-all                   Corre todos los hw/tb/**/tb_*.v (salvo tb_core_programs) y resume el resultado"
	@echo "  make sim-programs              Ensambla asm/tests/{h2,hazards,instr}, genera el .expected y corre cada programa en el nucleo,"
	@echo "                                 con enable fijo y con enable aleatorio"
	@echo "  make verify                    Verificacion cruzada (US-305): toda asm/ en el nucleo contra el golden model,"
	@echo "                                 con la tabla de ciclos/CPI en docs/informe/datos/cpi.csv"
	@echo "  make synth-ooc                 Sintesis fuera de contexto de hw/rtl/core con Vivado (recursos y latches)"
	@echo "       MOD=\"alu data_mem\"        solo esos modulos (por defecto, todos)"
	@echo "  make timing-core               Sintesis e implementacion fuera de contexto de riscv_core a 100 MHz"
	@echo "                                 (deja WNS/WHS en hw/reports/)"
	@echo "  make test-py                   Tests de Python con cobertura"
	@echo "  make check-py                  ruff + mypy + pytest + pip-audit"
	@echo "  make gnu-ref                   Regenera el .hex de referencia del ensamblador con GNU as (US-106)"
	@echo "  make check                     Todo: lint + sim-all + sim-programs + verify + check-py (lo mismo que corre el CI)"
	@echo "  make clean                     Borra build/ y las caches de Python"

# --- Instalacion de herramientas ---------------------------------------------------------

setup:
	sudo apt-get update
	sudo apt-get install -y make iverilog verilator curl binutils-riscv64-unknown-elf libsecret-1-0
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
	@WAVES=$(WAVES) HEX=$(HEX) EXPECTED=$(EXPECTED) ARGS="$(ARGS)" bash hw/scripts/sim.sh $(TB)

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

# Programas de asm/tests/{h2,hazards,instr} en el nucleo completo (US-210, US-301, US-304). Para cada uno: rvasm -> .hex,
# rvsim --expect -> .expected (golden model) y tb_core_programs con enable fijo y con enable
# aleatorio (AC4). Deja todo en build/programs/.
sim-programs:
	@mkdir -p $(BUILD_DIR)/programs
	@total=0; failed=0; \
	for p in $(PROGRAMS); do \
		src=$(CURDIR)/asm/tests/$$p.asm; out=$(CURDIR)/$(BUILD_DIR)/programs/$$p; \
		mkdir -p $$(dirname $$out); \
		if ! (cd $(TOOLS_DIR) && uv run python -m riscv_toolkit asm $$src -o $$out.hex > /dev/null 2>&1 \
				&& uv run python -m riscv_toolkit sim $$src --expect $$out.expected > /dev/null 2>&1); then \
			total=$$((total + 1)); failed=$$((failed + 1)); \
			printf '  FAIL  %-28s no ensambla o no termina en el golden model\n' $$p; continue; \
		fi; \
		for modo in fijo aleatorio; do \
			total=$$((total + 1)); \
			if [ $$modo = aleatorio ]; then extra="+ENABLE_ALEATORIO"; else extra=""; fi; \
			if QUIET=1 HEX=$$out.hex EXPECTED=$$out.expected ARGS="$$extra" \
					bash hw/scripts/sim.sh tb_core_programs > /dev/null 2>&1; then \
				printf '  PASS  %-28s enable %s\n' $$p $$modo; \
			else \
				failed=$$((failed + 1)); \
				cp $(BUILD_DIR)/tb_core_programs.log $$out.$$modo.log; \
				printf '  FAIL  %-28s enable %s   (ver %s)\n' $$p $$modo $(BUILD_DIR)/programs/$$p.$$modo.log; \
			fi; \
		done; \
	done; \
	echo; \
	echo "Programas: $$((total - failed)) de $$total corridas pasaron"; \
	[ $$total -gt 0 ] && [ $$failed -eq 0 ]

# Verificacion cruzada (US-305): ensambla cada programa de asm/, lo corre en el golden model y en
# tb_core_programs y compara el volcado final (registros, memoria usada, firma, motivo, PC).
# Muestra la tabla de ciclos, CPI, stalls y flushes y la guarda en docs/informe/datos/cpi.csv.
verify:
	@$(UV_RUN) python -m scripts.verify_rtl

# Sintesis fuera de contexto: LUTs, LUTRAM, FF, BRAM y latches por modulo (sin timing).
# Necesita Vivado 2025.2 en el PATH (o VIVADO=<ruta al ejecutable>). Deja build/synth/.
synth-ooc:
	@mkdir -p $(BUILD_DIR)/synth
	@cd $(BUILD_DIR)/synth && $(VIVADO) -mode batch -nojournal -nolog -notrace \
		-source ../../hw/scripts/synth_ooc.tcl -tclargs $(MOD) > vivado.log 2>&1; \
		status=$$?; sed -n '/^Sintesis fuera de contexto/,$$p' vivado.log; \
		[ $$status -eq 0 ] || echo "Vivado termino con error: ver $(BUILD_DIR)/synth/vivado.log"; \
		exit $$status

# Timing del nucleo fuera de contexto a 100 MHz (US-210 AC5). Deja los reportes en hw/reports/
# (se versionan para seguir la evolucion de WNS/WHS) y los temporales en build/timing/.
timing-core:
	@mkdir -p $(BUILD_DIR)/timing
	@cd $(BUILD_DIR)/timing && $(VIVADO) -mode batch -nojournal -nolog -notrace \
		-source ../../hw/scripts/timing_core_ooc.tcl > vivado.log 2>&1; \
		status=$$?; sed -n '/^riscv_core fuera de contexto/,$$p' vivado.log; \
		[ $$status -eq 0 ] || echo "Vivado termino con error: ver $(BUILD_DIR)/timing/vivado.log"; \
		exit $$status

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

check: lint sim-all sim-programs verify check-py

clean:
	rm -rf $(BUILD_DIR)
	find $(TOOLS_DIR) -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \) -prune -exec rm -rf {} +
	rm -f $(TOOLS_DIR)/.coverage
