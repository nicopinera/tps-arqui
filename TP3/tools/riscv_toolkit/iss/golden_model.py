"""Golden model: simulador de la ISA, una instrucción por paso (US-108, ADR-014).

Es la referencia contra la que se comparan la simulación RTL y la placa: ejecuta la semántica de
la §2.2 del PRD sin modelar el pipeline. Recibe palabras ya ensambladas, no texto (AC4): no
importa nada de `assembler/`.

Convenciones (ADR-008, ADR-009, ADR-018):
- Todo arranca en cero; la IMEM que no ocupa el programa se rellena con HALT.
- Los registros se guardan sin signo (0 … 2³² - 1); se interpretan con signo solo donde la
  instrucción lo pide (`slt`, `sra`, …) con `sign_extend`.
- Las direcciones fuera de rango dan la vuelta; los accesos desalineados ignoran los bits bajos
  y dejan una advertencia.
"""

import operator
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum, auto

from riscv_toolkit.isa.formatos import (
    decode_b,
    decode_i,
    decode_j,
    decode_r,
    decode_s,
    decode_u,
    sign_extend,
)
from riscv_toolkit.isa.instrucciones import HALT_WORD, Formato, identificar
from riscv_toolkit.protocol.comandos import DMEM_DEPTH, IMEM_DEPTH

_BYTES_PALABRA = 4
_MASCARA_32 = 0xFFFFFFFF
_SHAMT = 0x1F  # un shift usa solo 5 bits: correr 32 o más no tiene sentido en 32 bits


class Motivo(Enum):
    """Por qué terminó `run()`. TIMEOUT no existe en el hardware: es el corte del simulador."""

    HALTED = auto()
    ILLEGAL = auto()
    TIMEOUT = auto()


@dataclass(frozen=True)
class EstadoArquitectonico:
    """Estado final, con el mismo contenido que la parte de registros y memoria del snapshot."""

    regs: tuple[int, ...]  # x0 … x31, sin signo
    mem_usada: dict[int, int]  # dirección en bytes → palabra, solo las escritas (ADR-008)
    pc: int  # con ILLEGAL, el de la instrucción ilegal
    motivo: Motivo


# Operación de la ALU por mnemónico: recibe los dos operandos sin signo y devuelve el resultado.
# `add` y `addi` comparten entrada (cambia de dónde sale el segundo operando, no la operación).
_ALU: dict[str, Callable[[int, int], int]] = {
    "add": lambda a, b: (a + b) & _MASCARA_32,
    "sub": lambda a, b: (a - b) & _MASCARA_32,
    "sll": lambda a, b: (a << (b & _SHAMT)) & _MASCARA_32,
    "slt": lambda a, b: int(sign_extend(a, 32) < sign_extend(b, 32)),
    "sltu": lambda a, b: int(a < b),
    "xor": lambda a, b: a ^ b,
    "srl": lambda a, b: a >> (b & _SHAMT),  # a sin signo: >> rellena con ceros
    "sra": lambda a, b: (sign_extend(a, 32) >> (b & _SHAMT)) & _MASCARA_32,
    "or": lambda a, b: a | b,
    "and": lambda a, b: a & b,
}

# I de la ALU → la R que hace la misma operación. En slli/srli/srai el imm trae el funct7 en los
# bits altos (`srai` por 3 tiene imm 0x403): el `& _SHAMT` de la ALU lo descarta.
_ALU_INMEDIATO: dict[str, str] = {
    "addi": "add",
    "slti": "slt",
    "sltiu": "sltu",
    "xori": "xor",
    "ori": "or",
    "andi": "and",
    "slli": "sll",
    "srli": "srl",
    "srai": "sra",
}

# Load → (bytes que lee, si extiende el signo). `lw` ya trae 32 bits: no hay nada que extender.
_LOADS: dict[str, tuple[int, bool]] = {
    "lb": (1, True),
    "lh": (2, True),
    "lw": (4, False),
    "lbu": (1, False),
    "lhu": (2, False),
}
# Store → bytes que escribe (los bajos de rs2).
_STORES: dict[str, int] = {"sb": 1, "sh": 2, "sw": 4}
# Branch → condición para saltar. Comparan igualdad, así que el signo no importa.
_BRANCHES: dict[str, Callable[[int, int], bool]] = {"beq": operator.eq, "bne": operator.ne}


class GoldenModel:
    """Procesador RV32I (las 33 instrucciones de la tabla) ejecutado instrucción por instrucción.

    Uso típico:

        modelo = GoldenModel(imagen.palabras)
        motivo = modelo.run(max_instr=10_000)
        estado = modelo.estado_final()
    """

    pc: int
    regs: list[int]  # 32 registros; regs[0] siempre 0
    imem: list[int]  # IMEM_DEPTH palabras
    dmem: bytearray  # dmem_words · 4 bytes, little-endian
    mem_escrita: set[int]  # direcciones (en bytes, alineadas) de las palabras escritas
    instrucciones_retiradas: int
    advertencias: list[str]
    motivo: Motivo | None  # None mientras no terminó

    def __init__(
        self,
        imem_words: list[int],
        dmem_words: int = DMEM_DEPTH,
        imem_words_max: int = IMEM_DEPTH,
    ) -> None:
        if len(imem_words) > imem_words_max:
            raise ValueError(
                f"el programa tiene {len(imem_words)} palabras y la IMEM {imem_words_max}"
            )
        for i, palabra in enumerate(imem_words):
            if not 0 <= palabra <= _MASCARA_32:
                raise ValueError(f"la palabra {i} no entra en 32 bits: {palabra:#x}")

        faltan = imem_words_max - len(imem_words)
        self.imem = list(imem_words) + [HALT_WORD] * faltan  # el resto de la IMEM es HALT
        self.regs = [0] * 32
        self.pc = 0
        # una posicion = 1 byte (8 bits) -> una posicion en dmem son 4 bytes (32 bits)
        self.dmem = bytearray(dmem_words * _BYTES_PALABRA)
        self.mem_escrita = set()
        self.instrucciones_retiradas = 0
        self.advertencias = []
        self.motivo = None

    def step(self) -> Motivo | None:
        """Ejecuta una instrucción. Devuelve HALTED o ILLEGAL si con ella terminó, si no None.

        Una instrucción ilegal no modifica nada (ni el PC) ni cuenta como retirada.
        """
        palabra = self.imem[(self.pc // 4) % len(self.imem)]
        spec = identificar(palabra)
        if spec is None:
            self.motivo = Motivo.ILLEGAL
            return Motivo.ILLEGAL
        if spec.formato is Formato.HALT:
            self.motivo = Motivo.HALTED
            return Motivo.HALTED

        siguiente = self.pc + 4  # el camino normal; los saltos lo cambian
        if spec.formato is Formato.R:
            r = decode_r(palabra)
            self._escribir(r.rd, _ALU[spec.mnemonico](self.regs[r.rs1], self.regs[r.rs2]))
        elif spec.mnemonico in _ALU_INMEDIATO:
            i = decode_i(palabra)
            operacion = _ALU[_ALU_INMEDIATO[spec.mnemonico]]
            # el imm viene con signo (-1) y la ALU espera sin signo (0xFFFFFFFF)
            self._escribir(i.rd, operacion(self.regs[i.rs1], i.imm & _MASCARA_32))
        elif spec.mnemonico in _LOADS:
            i = decode_i(palabra)
            n, con_signo = _LOADS[spec.mnemonico]
            d = self._direccion(self.regs[i.rs1], i.imm, n, spec.mnemonico)
            valor = int.from_bytes(self.dmem[d : d + n], "little")
            if con_signo:
                valor = sign_extend(valor, 8 * n) & _MASCARA_32
            self._escribir(i.rd, valor)
        elif spec.mnemonico in _STORES:
            s = decode_s(palabra)
            n = _STORES[spec.mnemonico]
            d = self._direccion(self.regs[s.rs1], s.imm, n, spec.mnemonico)
            self.dmem[d : d + n] = (self.regs[s.rs2] & ((1 << 8 * n) - 1)).to_bytes(n, "little")
            self.mem_escrita.add(d & ~(_BYTES_PALABRA - 1))  # marca la palabra entera (ADR-008)
        elif spec.formato is Formato.B:
            b = decode_b(palabra)
            if _BRANCHES[spec.mnemonico](self.regs[b.rs1], self.regs[b.rs2]):
                siguiente = self.pc + b.imm  # relativo a esta instrucción, no a PC + 4
        elif spec.formato is Formato.J:
            j = decode_j(palabra)
            siguiente = self.pc + j.imm
            self._escribir(j.rd, self.pc + 4)
        elif spec.mnemonico == "jalr":
            i = decode_i(palabra)
            # el destino se calcula antes de escribir rd: en `jalr x1, 0(x1)` son el mismo
            siguiente = (self.regs[i.rs1] + i.imm) & ~1
            self._escribir(i.rd, self.pc + 4)
        elif spec.formato is Formato.U:
            u = decode_u(palabra)
            self._escribir(u.rd, u.imm)

        self.pc = siguiente & _MASCARA_32
        self.instrucciones_retiradas += 1
        return None

    def run(self, max_instr: int) -> Motivo:
        """Ejecuta hasta HALT, una ilegal o `max_instr` instrucciones (TIMEOUT).

        `max_instr` cuenta los pasos, incluido el del halt o la ilegal. Un loop infinito no
        cuelga: termina con TIMEOUT y el modelo queda donde estaba.
        """
        for _ in range(max_instr):
            motivo = self.step()
            if motivo is not None:
                return motivo
        self.motivo = Motivo.TIMEOUT
        return Motivo.TIMEOUT

    def estado_final(self) -> EstadoArquitectonico:
        """Estado al terminar `run()`. Falla si todavía no terminó."""
        if self.motivo is None:
            raise RuntimeError("el programa todavía no terminó: falta llamar a run()")
        mem_usada = {  # en orden de dirección creciente, como el snapshot (ADR-017)
            d: int.from_bytes(self.dmem[d : d + _BYTES_PALABRA], "little")
            for d in sorted(self.mem_escrita)
        }
        return EstadoArquitectonico(tuple(self.regs), mem_usada, self.pc, self.motivo)

    def _direccion(self, base: int, imm: int, n: int, mnemonico: str) -> int:
        """Índice en `dmem` de un acceso de `n` bytes a `base + imm` (ADR-008, ADR-018).

        Un acceso desalineado ignora los bits bajos y deja una advertencia; fuera de la DMEM
        la dirección da la vuelta.
        """
        direccion = (base + imm) & _MASCARA_32
        alineada = direccion & ~(n - 1)
        if alineada != direccion:
            self.advertencias.append(
                f"0x{self.pc:03x}: {mnemonico} desalineado en 0x{direccion:03x}, "
                f"se accede a 0x{alineada:03x}"
            )
        return alineada % len(self.dmem)

    def _escribir(self, rd: int, valor: int) -> None:
        """Escribe `valor` en `rd`, salvo en x0, que siempre vale 0."""
        if rd != 0:
            self.regs[rd] = valor
