"""Modelo del pipeline ciclo a ciclo (agregado US-306, `docs/agregado_golden_model.md`).

Un `ciclo()` es un flanco de reloj del núcleo de 5 etapas. Es la spec ejecutable de
`riscv_core.v`: mismos latches que el snapshot (ADR-017), mismas prioridades
(`riscv_core.md` §3). El golden model (`golden_model.py`) sigue siendo la referencia de ISA:
el estado final de los dos tiene que coincidir.

Cómo está armado, igual que el hardware:
1. `_combinacional()` calcula todo lo que el hardware calcula *durante* el ciclo, mirando
   solo el estado actual (PC, latches, banco, DMEM): cada etapa lee su latch de entrada y
   arma el valor que va a tener su latch de salida.
2. `ciclo()` aplica todo eso **de una vez**, como el flanco: ninguna etapa ve en este ciclo
   lo que otra escribió en este mismo ciclo.

Lo que modela (= el núcleo del Hito 3):
- flush: branch tomado / `jalr` en EX, `jal` en ID (ADR-006);
- HALT e ilegal (`halt_fetch`, terminar cuando llegan a WB), también especulativos;
- bypass del banco (ADR-007: WB escribe y ID lee el mismo registro en el mismo ciclo);
- Forwarding Unit (US-301) y Hazard Unit de load-use (US-302), con las prioridades de US-303;
- `stop_fetch` (ABORT, R-EJ-5): la Debug Unit lo prende y espera a que el pipeline se vacíe.

Decisiones (agregado §4):
- D1: el snapshot muestra el estado actual y los riesgos *de este ciclo* (lo que va a pasar
  en el próximo flanco), como lo muestrea la Debug Unit con el núcleo congelado.
- D2: termina en el flanco en que el HALT (o la ilegal) sale de WB; ese flanco cuenta.
  Al terminar, los 4 latches quedan con valid = 0 (US-210 AC2).
- D3: al terminar, el PC queda congelado por `halt_fetch` en (dirección del HALT) + 4.
- D4: `ciclos` arranca en 0 y suma uno por flanco.
"""

from dataclasses import dataclass

from riscv_toolkit.isa.control import (
    ALU_OP_ADD,
    ALU_OP_PASS_B,
    ALU_OP_R,
    RESULT_MEM,
    RESULT_PC4,
    Control,
    controlar,
    inmediato,
)
from riscv_toolkit.isa.formatos import decode_r, sign_extend
from riscv_toolkit.isa.instrucciones import HALT_WORD
from riscv_toolkit.iss.golden_model import _ALU, EstadoArquitectonico
from riscv_toolkit.iss.golden_model import Motivo as MotivoISS
from riscv_toolkit.protocol.comandos import DMEM_DEPTH, IMEM_DEPTH, EstadoDU, Motivo
from riscv_toolkit.protocol.snapshot import (
    LatchEXMEM,
    LatchIDEX,
    LatchIFID,
    LatchMEMWB,
    RiesgosCiclo,
    Snapshot,
)

_MASCARA_32 = 0xFFFFFFFF
# Selectores de forwarding (riscv_core.md §2.5), los mismos valores que viajan en el snapshot.
FWD_BANCO, FWD_MEM_WB, FWD_EX_MEM = 0b00, 0b01, 0b10

# alu_control (tabla_control.md §4): funct3 → operación, para alu_op = R (10) o I (11).
# funct3 000 y 101 dependen además de funct7_b5 (ver `_alu`).
_OPERACION = {
    0b000: "add",
    0b001: "sll",
    0b010: "slt",
    0b011: "sltu",
    0b100: "xor",
    0b101: "srl",
    0b110: "or",
    0b111: "and",
}
# Loads y stores: funct3 → bytes del acceso; los loads con signo (lb, lh) extienden.
_BYTES = {0b000: 1, 0b001: 2, 0b010: 4, 0b100: 1, 0b101: 2}
_CON_SIGNO = {0b000, 0b001}


def _alu(alu_op: int, funct3: int, funct7_b5: bool, a: int, b: int) -> int:
    """alu_control + ALU (US-201). La operación de cada nombre es la del golden model.

    shortcut: comparte `_ALU` con el golden model, así que un error en una operación no lo
    detecta la comparación entre los dos; lo cubren los tests propios del golden model.
    """
    if alu_op == ALU_OP_PASS_B:  # lui
        return b
    if alu_op == ALU_OP_ADD:  # loads, stores, jalr
        operacion = "add"
    else:
        operacion = _OPERACION[funct3]
        if funct3 == 0b000 and alu_op == ALU_OP_R and funct7_b5:
            operacion = "sub"  # addi nunca resta: en I el bit 30 es parte del inmediato
        elif funct3 == 0b101 and funct7_b5:
            operacion = "sra"  # srai sí lo mira: es el único I que lleva funct7
    return _ALU[operacion](a, b)


def _valor_wb(wb: LatchMEMWB) -> int:
    """El mux de WB (result_src): ALU, dato de memoria o PC+4."""
    if wb.result_src == RESULT_MEM:
        return wb.mem_data
    if wb.result_src == RESULT_PC4:
        return wb.pc_plus4
    return wb.alu_result


@dataclass(frozen=True)
class _Siguiente:
    """Lo que el hardware calculó durante el ciclo: se aplica todo junto en el flanco."""

    pc: int
    if_id: LatchIFID
    id_ex: LatchIDEX
    ex_mem: LatchEXMEM
    mem_wb: LatchMEMWB
    escritura_reg: tuple[int, int] | None  # (rd, valor): el puerto de escritura del banco
    escritura_mem: tuple[int, bytes] | None  # (índice en la DMEM, bytes): store_align
    halt_fetch: bool
    riesgos: RiesgosCiclo
    # Los cables combinacionales con el nombre del diagrama (datapath_pipeline.drawio), antes
    # de que un stall o un flush los tape: los muestra la vista Datapath de la GUI.
    cables: dict[str, int]


class ModeloPipeline:
    """El núcleo de 5 etapas, ciclo a ciclo.

    Uso típico:

        modelo = ModeloPipeline(imagen.palabras)
        modelo.correr(max_ciclos=10_000)
        estado = modelo.estado_final()
    """

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
        self.imem = list(imem_words) + [HALT_WORD] * (imem_words_max - len(imem_words))
        self.dmem = bytearray(dmem_words * 4)
        self.mem_escrita: set[int] = set()  # palabras escritas (bitmap de memoria usada)
        self.regs = [0] * 32
        self.pc = 0
        self.if_id, self.id_ex = LatchIFID(), LatchIDEX()
        self.ex_mem, self.mem_wb = LatchEXMEM(), LatchMEMWB()
        self.halt_fetch = False  # HALT/ilegal visto en ID: no se busca más (R-EJ-3)
        self.stop_fetch = False  # el pin i_stop_fetch: lo prende la Debug Unit en un ABORT
        self.motivo: Motivo | None = None  # HALTED / ILLEGAL al terminar
        self.ciclos = 0

    # --- Etapas (combinacional) -------------------------------------------------------------

    def _leer(self, n: int) -> int:
        """Puerto de lectura del banco, con bypass: si WB escribe `n` en este ciclo, ID ya ve
        el valor nuevo (ADR-007). Sin esto harían falta 3 NOPs entre dependencias y no 2."""
        wb = self.mem_wb
        if n != 0 and wb.valid and wb.reg_write and wb.rd == n:
            return _valor_wb(wb)
        return self.regs[n]

    def _direccion(self, direccion: int, n: int) -> int:
        """Índice en la DMEM: ignora los bits bajos si está desalineada y da la vuelta
        (ADR-008, ADR-018), igual que el golden model."""
        return (direccion & _MASCARA_32 & ~(n - 1)) % len(self.dmem)

    # --- Unidades de riesgo (US-301, US-302) ---------------------------------------------

    def _forwarding(self) -> tuple[int, int]:
        """Forwarding Unit (US-301, ADR-007): de dónde toma EX cada operando.

        Compara los registros que va a usar la instrucción que está en EX (ID/EX.rs1/rs2) con
        el destino de las dos que van adelante (EX/MEM.rd y MEM/WB.rd). 10 = desde EX/MEM,
        01 = desde MEM/WB, 00 = el valor que leyó ID del banco. Gana EX/MEM: es el más nuevo.
        """
        e, m, w = self.id_ex, self.ex_mem, self.mem_wb

        def fuente(rs: int) -> int:
            if m.valid and m.reg_write and m.rd != 0 and m.rd == rs:
                return FWD_EX_MEM
            if w.valid and w.reg_write and w.rd != 0 and w.rd == rs:
                return FWD_MEM_WB
            return FWD_BANCO

        return fuente(e.rs1), fuente(e.rs2)

    def _operando(self, fwd: int, del_banco: int) -> int:
        """El mux de forwarding de un operando."""
        if fwd == FWD_EX_MEM:
            return self.ex_mem.alu_result  # todavía no pasó por MEM: es el de la ALU
        if fwd == FWD_MEM_WB:
            return _valor_wb(self.mem_wb)  # el resultado final de WB (load, PC+4 o ALU)
        return del_banco

    def _load_use(self, c: Control, rs1: int, rs2: int) -> bool:
        """Hazard Unit, detección de load-use (US-302).

        Compara la instrucción que está en **ID** (IF/ID.rs1/rs2, solo si de verdad los lee:
        `uses_rs1/rs2` de la unidad de control) con un **load en EX** (ID/EX.mem_read y su rd).
        El dato del load recién existe al final de MEM: el forwarding no llega a tiempo, así
        que hay que esperar un ciclo.
        """
        e = self.id_ex
        if not (e.valid and e.mem_read and e.rd != 0):
            return False
        return bool((c.uses_rs1 and e.rd == rs1) or (c.uses_rs2 and e.rd == rs2))

    @property
    def vacio(self) -> bool:
        """Los 4 latches con valid = 0: así sabe la Debug Unit que terminó un ABORT."""
        return not any(x.valid for x in (self.if_id, self.id_ex, self.ex_mem, self.mem_wb))

    # --- Etapas (combinacional) -------------------------------------------------------------

    def _combinacional(self) -> _Siguiente:
        # WB: el puerto de escritura del banco (se escribe en el flanco).
        wb = self.mem_wb
        escritura_reg = (wb.rd, _valor_wb(wb)) if wb.valid and wb.reg_write and wb.rd else None

        # MEM: load_extend lee ya (lectura asíncrona de LUTRAM); el store se escribe en el flanco.
        m = self.ex_mem
        mem_data = 0
        escritura_mem = None
        if m.valid and (m.mem_read or m.mem_write):
            n = _BYTES[m.funct3]
            d = self._direccion(m.alu_result, n)
            if m.mem_read:
                mem_data = int.from_bytes(self.dmem[d : d + n], "little")
                if m.funct3 in _CON_SIGNO:
                    mem_data = sign_extend(mem_data, 8 * n) & _MASCARA_32
            if m.mem_write:  # store_align: los n bytes bajos de rs2
                escritura_mem = (d, (m.store_data & ((1 << 8 * n) - 1)).to_bytes(n, "little"))
        mem_wb = LatchMEMWB(
            alu_result=m.alu_result, mem_data=mem_data, pc_plus4=m.pc_plus4, rd=m.rd,
            valid=m.valid, halt=m.halt, illegal=m.illegal, reg_write=m.reg_write,
            result_src=m.result_src, instr=m.instr,
        )  # fmt: skip

        # EX: muxes de forwarding, ALU, branch_cmp y los destinos de branch y jalr.
        e = self.id_ex
        fwd_a, fwd_b = self._forwarding()
        a = self._operando(fwd_a, e.rs1_data)
        b = self._operando(fwd_b, e.rs2_data)  # también es store_data y entra a branch_cmp
        alu_result = _alu(e.alu_op, e.funct3, e.funct7_b5, a, e.imm if e.alu_src else b)
        tomado = e.branch and ((a == b) == (e.funct3 == 0b000))  # beq: iguales; bne: distintos
        redirige_ex = e.valid and (tomado or e.jalr)
        destino_ex = (alu_result & ~1) if e.jalr else (e.pc + e.imm) & _MASCARA_32
        ex_mem = LatchEXMEM(
            alu_result=alu_result, store_data=b, pc_plus4=e.pc_plus4, rd=e.rd, funct3=e.funct3,
            valid=e.valid, halt=e.halt, illegal=e.illegal, reg_write=e.reg_write,
            mem_read=e.mem_read, mem_write=e.mem_write, result_src=e.result_src, instr=e.instr,
        )  # fmt: skip

        # ID: unidad de control, imm_gen, lectura del banco, sumador de jal, detección de HALT.
        f = self.if_id
        c = controlar(f.instr) if f.valid else Control()  # una burbuja no prende nada
        campos = decode_r(f.instr)  # rs1, rs2, rd, funct3, funct7: mismo lugar en todo formato
        imm = inmediato(f.instr, c.imm_type)
        rs1_data, rs2_data = self._leer(campos.rs1), self._leer(campos.rs2)
        id_ex = LatchIDEX(
            pc=f.pc, pc_plus4=f.pc_plus4, rs1_data=rs1_data, rs2_data=rs2_data, imm=imm,
            rs1=campos.rs1, rs2=campos.rs2, rd=campos.rd, funct3=campos.funct3,
            alu_op=c.alu_op, valid=f.valid, reg_write=bool(c.reg_write),
            mem_read=bool(c.mem_read), mem_write=bool(c.mem_write), alu_src=bool(c.alu_src),
            branch=bool(c.branch), jump=bool(c.jump), jalr=bool(c.jalr), halt=bool(c.halt),
            illegal=bool(c.illegal), funct7_b5=bool(campos.funct7 >> 5 & 1),
            result_src=c.result_src, instr=f.instr,
        )  # fmt: skip
        salta_jal = f.valid and bool(c.jump)
        detecta_halt = f.valid and bool(c.halt)
        load_use = self._load_use(c, campos.rs1, campos.rs2)

        # IF: buscar la instrucción del PC.
        if_id = LatchIFID(
            self.pc, (self.pc + 4) & _MASCARA_32, self.imem[(self.pc // 4) % len(self.imem)], True
        )
        pc = (self.pc + 4) & _MASCARA_32

        # Próximo PC y latches, de mayor a menor prioridad (riscv_core.md §3).
        halt_fetch = self.halt_fetch
        stall = False
        if redirige_ex:  # 5: lo que está en IF e ID entró por error → 2 burbujas
            pc = destino_ex
            if_id, id_ex = LatchIFID(), LatchIDEX()
        elif salta_jal:  # 6: lo que está en IF entró por error → 1 burbuja; jal sigue
            pc = (f.pc + imm) & _MASCARA_32
            if_id = LatchIFID()
        elif load_use:  # 7: el dato del load no existe todavía → esperar un ciclo
            stall = True
            pc, if_id = self.pc, self.if_id  # PC e IF/ID no cambian (sin enable)
            id_ex = LatchIDEX()  # y a EX entra una burbuja
        elif detecta_halt:  # 8: un HALT tapado por una redirección era especulativo y no vale
            halt_fetch = True
        if halt_fetch:  # PC congelado y burbujas en IF/ID hasta terminar
            pc = self.pc
            if_id = LatchIFID()
        if self.stop_fetch:  # ABORT: no se busca más y lo que está en ID se descarta
            pc = self.pc
            if_id, id_ex = LatchIFID(), LatchIDEX()
            stall = False

        cables = {
            # IF
            "pcF": self.pc, "pc_plus4F": (self.pc + 4) & _MASCARA_32,
            "instrF": self.imem[(self.pc // 4) % len(self.imem)], "validF": 1,
            # ID: lo que sale de la unidad de control, el banco y imm_gen hacia ID/EX
            "op": f.instr & 0x7F, "funct3": campos.funct3, "funct7": campos.funct7,
            "rs1D": campos.rs1, "rs2D": campos.rs2, "rdD": campos.rd,
            "funct3D": campos.funct3, "funct7_b5D": campos.funct7 >> 5 & 1,
            "rs1_dataD": rs1_data, "rs2_dataD": rs2_data, "immD": imm,
            "imm_type": c.imm_type, "reg_writeD": c.reg_write, "result_srcD": c.result_src,
            "mem_readD": c.mem_read, "mem_writeD": c.mem_write, "alu_srcD": c.alu_src,
            "alu_opD": c.alu_op, "branchD": c.branch, "jumpD": c.jump, "jalrD": c.jalr,
            "haltD": c.halt, "illegalD": c.illegal, "uses_rs1": c.uses_rs1,
            "uses_rs2": c.uses_rs2, "jal_target": (f.pc + imm) & _MASCARA_32,
            # EX
            "srcA": a, "srcB": e.imm if e.alu_src else b, "store_data": b,
            "alu_resultE": alu_result, "eq": int(a == b),
            "branch_target": (e.pc + e.imm) & _MASCARA_32, "jalr_target": alu_result & ~1,
            "ex_target": destino_ex, "redirect_ex": int(redirige_ex),
            # MEM y WB
            "mem_dataM": mem_data, "ResultW": _valor_wb(wb),
            # Hazard Unit (guía de riesgos §7.1)
            "pc_sel": 0b10 if redirige_ex else 0b01 if salta_jal else 0b00,
            "StallF": int(stall or halt_fetch or self.stop_fetch), "StallD": int(stall),
            "FlushD": int(redirige_ex or salta_jal or halt_fetch or self.stop_fetch),
            "FlushE": int(redirige_ex or stall or self.stop_fetch),
        }  # fmt: skip

        return _Siguiente(
            pc=pc, if_id=if_id, id_ex=id_ex, ex_mem=ex_mem, mem_wb=mem_wb,
            escritura_reg=escritura_reg, escritura_mem=escritura_mem, halt_fetch=halt_fetch,
            riesgos=RiesgosCiclo(
                stall=stall, flush_if_id=redirige_ex or salta_jal, flush_id_ex=redirige_ex,
                fwd_a=fwd_a, fwd_b=fwd_b,
            ),
            cables=cables,
        )  # fmt: skip

    # --- Flanco -----------------------------------------------------------------------------

    def ciclo(self) -> None:
        """Un flanco de reloj. Después de terminar no hace nada (el núcleo ignora i_enable)."""
        if self.motivo is not None:
            return
        s = self._combinacional()
        retira = self.mem_wb  # lo que sale de WB en este flanco
        if s.escritura_reg is not None:
            rd, valor = s.escritura_reg
            self.regs[rd] = valor
        if s.escritura_mem is not None:
            d, datos = s.escritura_mem
            self.dmem[d : d + len(datos)] = datos
            self.mem_escrita.add(d & ~3)  # marca la palabra entera (ADR-008)
        self.pc, self.halt_fetch = s.pc, s.halt_fetch
        self.if_id, self.id_ex, self.ex_mem, self.mem_wb = s.if_id, s.id_ex, s.ex_mem, s.mem_wb
        self.ciclos += 1
        if retira.valid and retira.halt:  # D2: termina cuando el HALT sale de WB
            self.motivo = Motivo.ILLEGAL if retira.illegal else Motivo.HALTED

    def correr(self, max_ciclos: int) -> Motivo | None:
        """Ciclos hasta terminar o hasta `max_ciclos`. None si no terminó (un loop infinito)."""
        for _ in range(max_ciclos):
            if self.motivo is not None:
                break
            self.ciclo()
        return self.motivo

    # --- Lo que se ve desde afuera ----------------------------------------------------------

    def snapshot(self, estado: EstadoDU | None = None) -> Snapshot:
        """El snapshot de este ciclo (D1), con el mismo formato que manda la placa."""
        riesgos = self._combinacional().riesgos if self.motivo is None else RiesgosCiclo()
        if estado is None:
            estado = EstadoDU.STEPPING if self.motivo is None else EstadoDU.HALTED
        return Snapshot(
            estado=estado,
            motivo=self.motivo,
            ciclos=self.ciclos,
            pc=self.pc,
            riesgos=riesgos,
            regs=tuple(self.regs),
            if_id=self.if_id,
            id_ex=self.id_ex,
            ex_mem=self.ex_mem,
            mem_wb=self.mem_wb,
            mem_usada=self._mem_usada(),
            simulado=True,
        )

    def cables(self) -> dict[str, int]:
        """Los cables combinacionales de este ciclo, con el nombre del diagrama."""
        return self._combinacional().cables

    @classmethod
    def desde_snapshot(cls, snap: Snapshot, imem_words: list[int]) -> "ModeloPipeline":
        """El modelo en el estado de un snapshot (de la placa o del fake), para recalcular los
        cables combinacionales que el snapshot no trae.

        `halt_fetch` no viaja en el snapshot, pero se deduce: se prende con el HALT en ID, y
        al ciclo siguiente ese HALT está en EX; desde ahí hasta que sale de WB hay un HALT
        válido en ID/EX, EX/MEM o MEM/WB. `stop_fetch` (ABORT) no se puede deducir: queda en 0.
        """
        modelo = cls(imem_words)
        modelo.regs, modelo.pc, modelo.ciclos = list(snap.regs), snap.pc, snap.ciclos
        modelo.if_id, modelo.id_ex, modelo.ex_mem, modelo.mem_wb = (
            snap.if_id,
            snap.id_ex,
            snap.ex_mem,
            snap.mem_wb,
        )
        modelo.halt_fetch = any(x.valid and x.halt for x in (snap.id_ex, snap.ex_mem, snap.mem_wb))
        modelo.motivo = snap.motivo
        for direccion, palabra in snap.mem_usada.items():  # el resto de la DMEM vale 0 (ADR-008)
            modelo.dmem[direccion : direccion + 4] = palabra.to_bytes(4, "little")
            modelo.mem_escrita.add(direccion)
        return modelo

    def _mem_usada(self) -> dict[int, int]:
        return {d: int.from_bytes(self.dmem[d : d + 4], "little") for d in sorted(self.mem_escrita)}

    def estado_final(self) -> EstadoArquitectonico:
        """Para comparar con `GoldenModel.estado_final()`. Falla si todavía no terminó."""
        if self.motivo is None:
            raise RuntimeError("el programa todavía no terminó: falta correr()")
        motivo = MotivoISS.ILLEGAL if self.motivo is Motivo.ILLEGAL else MotivoISS.HALTED
        return EstadoArquitectonico(tuple(self.regs), self._mem_usada(), self.pc, motivo)
