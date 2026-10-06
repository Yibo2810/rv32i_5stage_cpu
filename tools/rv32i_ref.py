#!/usr/bin/env python3
"""Small RV32I reference model for this repo's directed core tests.

The model intentionally matches the current SystemVerilog harness:
- hex word 0 sits at --base (default 0, the reset PC); programs linked for
  Spike / the FPGA SoC use --base 0x80000000
- data memory is a sparse 32-bit word array addressed by addr[9:2] in RTL
- stores update byte lanes using dmem_wstrb
- output is the expected-file format consumed by core_sv_tb.sv

This is not a full platform simulator. It is a local oracle for simple RV32I
bare-metal snippets used by the core-level testbench.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


MASK32 = 0xFFFFFFFF


class RefError(RuntimeError):
    pass


@dataclass(frozen=True)
class MemTxn:
    kind: str
    addr: int
    data: int
    wstrb: int


def u32(value: int) -> int:
    return value & MASK32


def bit(value: int, index: int) -> int:
    return (value >> index) & 1


def bits(value: int, hi: int, lo: int) -> int:
    return (value >> lo) & ((1 << (hi - lo + 1)) - 1)


def sign_extend(value: int, width: int) -> int:
    sign = 1 << (width - 1)
    mask = (1 << width) - 1
    value &= mask
    return value - (1 << width) if value & sign else value


def signed32(value: int) -> int:
    return sign_extend(value, 32)


def imm_i(instr: int) -> int:
    return sign_extend(bits(instr, 31, 20), 12)


def imm_s(instr: int) -> int:
    raw = (bits(instr, 31, 25) << 5) | bits(instr, 11, 7)
    return sign_extend(raw, 12)


def imm_b(instr: int) -> int:
    raw = (
        (bit(instr, 31) << 12)
        | (bit(instr, 7) << 11)
        | (bits(instr, 30, 25) << 5)
        | (bits(instr, 11, 8) << 1)
    )
    return sign_extend(raw, 13)


def imm_u(instr: int) -> int:
    return instr & 0xFFFFF000


def imm_j(instr: int) -> int:
    raw = (
        (bit(instr, 31) << 20)
        | (bits(instr, 19, 12) << 12)
        | (bit(instr, 20) << 11)
        | (bits(instr, 30, 21) << 1)
    )
    return sign_extend(raw, 21)


def load_hex(path: Path) -> list[int]:
    words: list[int] = []
    for lineno, line in enumerate(path.read_text().splitlines(), start=1):
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        try:
            words.append(int(text, 16) & MASK32)
        except ValueError as exc:
            raise RefError(f"{path}:{lineno}: bad hex word: {text}") from exc
    return words


class RV32IRef:
    def __init__(self, instrs: list[int], max_steps: int, base: int = 0) -> None:
        self.instrs = instrs
        self.max_steps = max_steps
        self.base = base
        self.pc = base
        self.regs = [0] * 32
        self.dmem: dict[int, int] = {}
        self.written_word_indices: set[int] = set()
        self.txns: list[MemTxn] = []

    def run(self) -> None:
        for _ in range(self.max_steps):
            if self.pc & 0x3:
                raise RefError(f"misaligned PC: 0x{self.pc:08x}")
            if self.pc < self.base:
                raise RefError(f"PC below text base: pc=0x{self.pc:08x} base=0x{self.base:08x}")
            index = (self.pc - self.base) >> 2
            if index >= len(self.instrs):
                return
            self.step(self.instrs[index])
            self.regs[0] = 0
        raise RefError(f"max steps reached before PC left program: {self.max_steps}")

    def read_word(self, addr: int) -> int:
        return self.dmem.get((addr & MASK32) >> 2, 0)

    def write_masked_word(self, addr: int, wdata: int, wstrb: int) -> None:
        word_index = (addr & MASK32) >> 2
        old = self.dmem.get(word_index, 0)
        new = old
        for byte in range(4):
            if (wstrb >> byte) & 1:
                lane = (wdata >> (8 * byte)) & 0xFF
                new &= ~(0xFF << (8 * byte))
                new |= lane << (8 * byte)
        self.dmem[word_index] = u32(new)
        self.written_word_indices.add(word_index)

    def add_txn(self, kind: str, addr: int, data: int, wstrb: int) -> None:
        self.txns.append(MemTxn(kind, u32(addr), u32(data), wstrb & 0xF))

    def step(self, instr: int) -> None:
        opcode = bits(instr, 6, 0)
        rd = bits(instr, 11, 7)
        funct3 = bits(instr, 14, 12)
        rs1 = bits(instr, 19, 15)
        rs2 = bits(instr, 24, 20)
        funct7 = bits(instr, 31, 25)
        pc = self.pc
        next_pc = u32(pc + 4)

        if opcode == 0x33:
            self.exec_rtype(rd, rs1, rs2, funct3, funct7)
        elif opcode == 0x13:
            self.exec_itype(rd, rs1, funct3, funct7, rs2, imm_i(instr))
        elif opcode == 0x03:
            self.exec_load(rd, rs1, funct3, imm_i(instr))
        elif opcode == 0x23:
            self.exec_store(rs1, rs2, funct3, imm_s(instr))
        elif opcode == 0x63:
            if self.branch_taken(rs1, rs2, funct3):
                next_pc = u32(pc + imm_b(instr))
        elif opcode == 0x6F:
            self.write_reg(rd, pc + 4)
            next_pc = u32(pc + imm_j(instr))
        elif opcode == 0x67:
            if funct3 != 0x0:
                raise RefError(f"unsupported JALR funct3 at PC 0x{pc:08x}: {funct3}")
            target = u32(self.regs[rs1] + imm_i(instr)) & ~1
            self.write_reg(rd, pc + 4)
            next_pc = target
        elif opcode == 0x37:
            self.write_reg(rd, imm_u(instr))
        elif opcode == 0x17:
            self.write_reg(rd, pc + imm_u(instr))
        else:
            raise RefError(f"unsupported opcode at PC 0x{pc:08x}: instr=0x{instr:08x}")

        self.pc = next_pc

    def write_reg(self, rd: int, value: int) -> None:
        if rd != 0:
            self.regs[rd] = u32(value)

    def exec_rtype(self, rd: int, rs1: int, rs2: int, funct3: int, funct7: int) -> None:
        a = self.regs[rs1]
        b = self.regs[rs2]
        shamt = b & 0x1F

        if funct3 == 0x0 and funct7 == 0x00:
            result = a + b
        elif funct3 == 0x0 and funct7 == 0x20:
            result = a - b
        elif funct3 == 0x7 and funct7 == 0x00:
            result = a & b
        elif funct3 == 0x6 and funct7 == 0x00:
            result = a | b
        elif funct3 == 0x4 and funct7 == 0x00:
            result = a ^ b
        elif funct3 == 0x1 and funct7 == 0x00:
            result = a << shamt
        elif funct3 == 0x5 and funct7 == 0x00:
            result = a >> shamt
        elif funct3 == 0x5 and funct7 == 0x20:
            result = signed32(a) >> shamt
        elif funct3 == 0x2 and funct7 == 0x00:
            result = 1 if signed32(a) < signed32(b) else 0
        elif funct3 == 0x3 and funct7 == 0x00:
            result = 1 if a < b else 0
        else:
            raise RefError(f"unsupported R-type funct7/funct3: {funct7:02x}/{funct3:x}")

        self.write_reg(rd, result)

    def exec_itype(
        self,
        rd: int,
        rs1: int,
        funct3: int,
        funct7: int,
        shamt_field: int,
        immediate: int,
    ) -> None:
        a = self.regs[rs1]

        if funct3 == 0x0:
            result = a + immediate
        elif funct3 == 0x2:
            result = 1 if signed32(a) < immediate else 0
        elif funct3 == 0x3:
            result = 1 if a < u32(immediate) else 0
        elif funct3 == 0x4:
            result = a ^ u32(immediate)
        elif funct3 == 0x6:
            result = a | u32(immediate)
        elif funct3 == 0x7:
            result = a & u32(immediate)
        elif funct3 == 0x1 and funct7 == 0x00:
            result = a << shamt_field
        elif funct3 == 0x5 and funct7 == 0x00:
            result = a >> shamt_field
        elif funct3 == 0x5 and funct7 == 0x20:
            result = signed32(a) >> shamt_field
        else:
            raise RefError(f"unsupported I-type funct7/funct3: {funct7:02x}/{funct3:x}")

        self.write_reg(rd, result)

    def branch_taken(self, rs1: int, rs2: int, funct3: int) -> bool:
        a = self.regs[rs1]
        b = self.regs[rs2]

        if funct3 == 0x0:
            return a == b
        if funct3 == 0x1:
            return a != b
        if funct3 == 0x4:
            return signed32(a) < signed32(b)
        if funct3 == 0x5:
            return signed32(a) >= signed32(b)
        if funct3 == 0x6:
            return a < b
        if funct3 == 0x7:
            return a >= b
        raise RefError(f"unsupported branch funct3: {funct3:x}")

    def exec_load(self, rd: int, rs1: int, funct3: int, immediate: int) -> None:
        addr = u32(self.regs[rs1] + immediate)
        offset = addr & 0x3
        rdata = self.read_word(addr)

        if funct3 == 0x0:
            self.add_txn("R", addr, rdata, 0)
            value = sign_extend((rdata >> (8 * offset)) & 0xFF, 8)
        elif funct3 == 0x1:
            if offset & 0x1:
                return
            self.add_txn("R", addr, rdata, 0)
            value = sign_extend((rdata >> (8 * offset)) & 0xFFFF, 16)
        elif funct3 == 0x2:
            if offset != 0:
                return
            self.add_txn("R", addr, rdata, 0)
            value = rdata
        elif funct3 == 0x4:
            self.add_txn("R", addr, rdata, 0)
            value = (rdata >> (8 * offset)) & 0xFF
        elif funct3 == 0x5:
            if offset & 0x1:
                return
            self.add_txn("R", addr, rdata, 0)
            value = (rdata >> (8 * offset)) & 0xFFFF
        else:
            raise RefError(f"unsupported load funct3: {funct3:x}")

        self.write_reg(rd, value)

    def exec_store(self, rs1: int, rs2: int, funct3: int, immediate: int) -> None:
        addr = u32(self.regs[rs1] + immediate)
        offset = addr & 0x3
        store_data = self.regs[rs2]

        if funct3 == 0x0:
            wdata = (store_data & 0xFF) << (8 * offset)
            wstrb = 0x1 << offset
        elif funct3 == 0x1:
            if offset & 0x1:
                return
            wdata = (store_data & 0xFFFF) << (8 * offset)
            wstrb = 0x3 << offset
        elif funct3 == 0x2:
            if offset != 0:
                return
            wdata = store_data
            wstrb = 0xF
        else:
            raise RefError(f"unsupported store funct3: {funct3:x}")

        self.add_txn("W", addr, wdata, wstrb)
        self.write_masked_word(addr, wdata, wstrb)

    def signature_words(self) -> list[tuple[int, int]]:
        result = []
        for word_index in sorted(self.written_word_indices):
            result.append((word_index << 2, self.dmem.get(word_index, 0)))
        return result


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root_from_script()).as_posix()
    except ValueError:
        return path.as_posix()


def render_expected(hex_path: Path, model: RV32IRef) -> str:
    lines = [
        f"# generated by tools/rv32i_ref.py from {display_path(hex_path)}",
        f"# txns={len(model.txns)} signatures={len(model.written_word_indices)}",
    ]
    if model.base:
        lines.append(f"# base=0x{model.base:08x}")
    for txn in model.txns:
        lines.append(f"TXN {txn.kind} {txn.addr:08x} {txn.data:08x} {txn.wstrb:04b}")
    for addr, data in model.signature_words():
        lines.append(f"SIG {addr:08x} {data:08x}")
    lines.append("")
    return "\n".join(lines)


def run_hex(hex_path: Path, max_steps: int, base: int = 0) -> str:
    instrs = load_hex(hex_path)
    model = RV32IRef(instrs, max_steps=max_steps, base=base)
    model.run()
    return render_expected(hex_path, model)


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_hex_arg(arg: str, repo_root: Path, hex_dir: Path) -> Path:
    raw = Path(arg)
    candidates: list[Path]
    if raw.suffix:
        candidates = [raw, repo_root / raw]
    else:
        candidates = [hex_dir / f"{arg}.hex", raw, repo_root / raw]

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise RefError(f"hex file not found for argument: {arg}")


def write_expected(hex_path: Path, expected_dir: Path, text: str) -> Path:
    expected_dir.mkdir(parents=True, exist_ok=True)
    out_path = expected_dir / f"{hex_path.stem}.expected"
    out_path.write_text(text)
    return out_path


def iter_all_hex(hex_dir: Path) -> Iterable[Path]:
    yield from sorted(hex_dir.glob("*.hex"))


def parse_args() -> argparse.Namespace:
    repo_root = repo_root_from_script()
    parser = argparse.ArgumentParser(
        description="Generate expected TXN/SIG files from RV32I hex programs."
    )
    parser.add_argument("hex", nargs="*", help="hex file, test name, or path")
    parser.add_argument("--all", action="store_true", help="generate expected for every programs/hex/*.hex")
    parser.add_argument("--stdout", action="store_true", help="print generated expected instead of writing files")
    parser.add_argument("--max-steps", type=int, default=1024, help="maximum instructions to execute")
    parser.add_argument(
        "--base",
        type=lambda value: int(value, 0),
        default=0,
        help="address of hex word 0 = reset PC (default 0; 0x80000000 for Spike-linked programs)",
    )
    parser.add_argument("--hex-dir", type=Path, default=repo_root / "programs" / "hex")
    parser.add_argument("--expected-dir", type=Path, default=repo_root / "programs" / "expected")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_from_script()
    hex_dir = args.hex_dir.resolve()
    expected_dir = args.expected_dir.resolve()
    if args.base & 0x3 or not (0 <= args.base <= 0xFFFFFFFF):
        raise RefError(f"--base must be a 4-byte aligned 32-bit address: 0x{args.base:x}")

    if args.all:
        hex_paths = list(iter_all_hex(hex_dir))
        if not hex_paths:
            raise RefError(f"no .hex files found in {hex_dir}")
    else:
        if not args.hex:
            raise RefError("provide at least one hex/test name, or use --all")
        hex_paths = [resolve_hex_arg(item, repo_root, hex_dir) for item in args.hex]

    for hex_path in hex_paths:
        text = run_hex(hex_path, args.max_steps, args.base)
        if args.stdout:
            print(text, end="")
        else:
            out_path = write_expected(hex_path, expected_dir, text)
            print(f"generated {out_path}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RefError as exc:
        raise SystemExit(f"rv32i_ref.py: {exc}")
