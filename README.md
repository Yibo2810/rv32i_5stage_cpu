# RV32I 5-Stage CPU

A learning-oriented RV32I CPU project implemented in Verilog and
SystemVerilog.

The project has completed its **v0.3.0 single-cycle verification milestone**.
The current release focuses on a complete single-cycle RV32I integer datapath
for the supported base instructions, a reusable SystemVerilog verification
harness, VCS simulation, directed assembly regressions, and generated expected
results. The next major phase is constrained-random verification and development
of a classic five-stage pipeline.

## Current Milestone

**v0.3.0: verified single-cycle core**

This release promotes the single-cycle core from a small smoke-test baseline to
a broader core-level directed regression. The RTL supports and the VCS
SystemVerilog regression verifies:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, slti, sltiu, xori, ori, andi, slli, srli, srai
lb, lh, lw, lbu, lhu, sb, sh, sw
beq, bne, blt, bge, bltu, bgeu
jal, jalr, lui, auipc
```

The release also verifies important architectural behavior such as `x0` write
protection, branch taken/not-taken behavior, byte/halfword memory masks, signed
and unsigned loads, jump redirects, upper immediates, and final data-memory
signatures.

System and environment instructions such as `fence`, `ecall`, and `ebreak` are
not part of this milestone. They are intentionally deferred until the project
has a clearer exception/trap model.

## Status

- [x] Project structure and documentation scaffold
- [x] Shared RV32I constants and control encodings
- [x] Single-cycle RTL for PC, register file, ALU, immediate generation, control, load/store, redirect, and writeback
- [x] Byte/halfword/word load-store behavior with byte write strobes
- [x] Full RV32I branch family for the single-cycle core
- [x] `jal`, `jalr`, `lui`, and `auipc` support
- [x] VCS-based SystemVerilog testbench
- [x] Reusable `core_mem_if`, `core_memory_model`, monitor, scoreboard, and assertion scaffold
- [x] Directed assembly tests for R-type ALU, I-type ALU, load/store widths, branches, jumps, upper immediates, and `x0`
- [x] Python reference model for generated `TXN` and `SIG` expected files
- [x] Core-level directed regression passing under VCS
- [ ] Constrained-random program generation
- [ ] Functional coverage closure
- [ ] Commit/retire monitor for pipeline-friendly checking
- [ ] Five-stage pipeline implementation
- [ ] Forwarding, hazard detection, stalls, and flushes

## Verification Summary

Primary release command sequence:

```sh
./scripts/asm_to_hex.sh
./tools/rv32i_ref.py --all
make run
```

Validated on `yibo-server` with Synopsys VCS `W-2024.09-SP1`:

```text
ALL CORE SV TESTS PASSED
```

The v0.3.0 directed regression contains:

| Test | Main coverage | Checker style |
|---|---|---|
| `x0_test` | Writes to `x0` ignored, reads from `x0` return zero | memory transactions + final signatures |
| `alu_itype_test` | ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI | memory transactions + final signatures |
| `alu_rtype_test` | ADD/SUB/AND/OR/XOR/SLT/SLTU/SLL/SRL/SRA | memory transactions + final signatures |
| `load_store_width_test` | SB/SH/SW/LB/LBU/LH/LHU, byte masks, signedness | memory transactions + final signatures |
| `branch_matrix_test` | BEQ/BNE/BLT/BGE/BLTU/BGEU taken and not-taken | memory transactions + final signatures |
| `jump_u_type_test` | LUI/AUIPC/JAL/JALR redirect and writeback behavior | memory transactions + final signatures |

## Verification Architecture

The release verification flow is intentionally split into stable layers:

```text
programs/asm/*.S
  -> scripts/asm_to_hex.sh
  -> programs/hex/*.hex
  -> tools/rv32i_ref.py
  -> programs/expected/*.expected
  -> tb/sv/core/core_sv_tb.sv
  -> core_memory_model + core_monitor + core_scoreboard
  -> PASS/FAIL from TXN and SIG checks
```

Important files:

| Path | Role |
|---|---|
| `rtl/include/single_pkg.sv` | Shared SystemVerilog RV32I constants and control types |
| `rtl/single_cycle/` | Current verified single-cycle CPU RTL |
| `rtl/pipeline/` | Placeholder area for the next five-stage pipeline phase |
| `tb/sv/core/core_sv_tb.sv` | VCS top-level SystemVerilog harness |
| `tb/sv/core/core_verif_pkg.sv` | Shared verification structs and enums |
| `tb/sv/core/core_test_db.sv` | Test metadata database: name, hex path, expected path, max cycles |
| `tb/sv/core/core_mem_if.sv` | Instruction/data memory interface boundary |
| `tb/sv/core/core_memory_model.sv` | Unified instruction/data memory model with byte-enable writes and `peek_word` |
| `tb/sv/core/core_monitor.sv` | Passive capture of observed memory transactions |
| `tb/sv/core/core_scoreboard.sv` | Expected-vs-observed transaction and signature checks |
| `tb/sv/core/core_assertions.sv` | Early assertion scaffold for protocol and invariant checks |
| `tb/filelists/core_sv.f` | VCS compile filelist |
| `programs/asm/` | Directed assembly tests |
| `programs/hex/` | Generated instruction-memory images |
| `programs/expected/` | Generated expected `TXN` and `SIG` files |
| `tools/rv32i_ref.py` | Small repository-specific RV32I reference model |
| `docs/` | Architecture, ISA, verification, and milestone notes |

The checker has two levels:

- Transaction checks compare observed memory reads/writes against generated
  expected `TXN` entries.
- Signature checks use final data-memory words as architectural test results.

This keeps the verification architecture useful for the future pipeline: the
test programs, expected files, and scoreboard can stay mostly stable while the
monitor moves from a single-cycle bus view to a commit/retire view.

## Running The Project

Generate all directed hex programs:

```sh
./scripts/asm_to_hex.sh
```

Generate all expected files:

```sh
./tools/rv32i_ref.py --all
```

Build and run the VCS regression:

```sh
make run
```

Compile only:

```sh
make build
```

The default `Makefile` builds `core_sv_tb` using `tb/filelists/core_sv.f` and
writes simulation output under `sim/build/core_vcs/`.

## Repository Layout

```text
.
├── Makefile
├── README.md
├── docs/
├── programs/
│   ├── asm/
│   ├── expected/
│   └── hex/
├── rtl/
│   ├── include/
│   ├── pipeline/
│   └── single_cycle/
├── tb/
│   ├── filelists/
│   └── sv/core/
├── tools/
└── sim/
```

## Known Limitations

- The release verifies the supported RV32I single-cycle datapath with directed
  tests. It is not yet constrained-random verification or coverage closure.
- The reference model in `tools/rv32i_ref.py` is a repository-specific oracle for
  current bare-metal snippets, not a full architectural simulator.
- `fence`, `ecall`, `ebreak`, privileged behavior, traps, interrupts, CSRs, and
  real bus wait states are out of scope for v0.3.0.
- The pipeline files under `rtl/pipeline/` are placeholders for the next phase,
  not a verified five-stage implementation.
- The current monitor focuses on memory transactions. A richer commit/retire
  monitor is planned before serious pipeline verification.
- The VCS compile log may contain non-fatal package import notes from current
  source style.

## Roadmap

1. Add lightweight functional coverage for opcode groups, branch direction,
   load/store width, byte strobes, redirects, and `x0` behavior.
2. Add more assertions for PC alignment, memory access rules, legal byte
   enables, and no-X checks on active transactions.
3. Build a constrained-random program generator using deterministic seeds and
   `tools/rv32i_ref.py` expected generation.
4. Add a commit/retire monitor so the same scoreboard concepts can survive the
   single-cycle to pipeline transition.
5. Implement the five-stage pipeline: IF, ID, EX, MEM, WB.
6. Add forwarding, load-use stall handling, branch flushes, and pipeline-focused
   directed/random regressions.
