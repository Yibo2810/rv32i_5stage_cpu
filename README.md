# RV32I 5-Stage CPU

A learning-oriented RV32I CPU project implemented in Verilog and
SystemVerilog.

The project has completed its **v0.4.0 constrained-random verification
milestone**. The single-cycle RV32I core is now verified by a seed-reproducible
constrained-random regression checked against an in-testbench ISS reference
model, guarded by concurrent assertions, and measured by a functional coverage
model closed to 100% of its defined bins — all running under VCS. The next
major phase is the classic five-stage pipeline.

## Current Milestone

**v0.4.0: constrained-random verification freeze**
(see [docs/09_v0_4_0_milestone.md](docs/09_v0_4_0_milestone.md))

Each random seed builds a structured program (straight-line code, bounded
loops, forward branches with controlled outcomes, JALR blocks, store→load
pairs), runs it on the RTL and an ISS in lockstep, and compares the full
memory transaction stream, the final register file, and the retire
count/final PC. The supported and verified instruction subset:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, slti, sltiu, xori, ori, andi, slli, srli, srai
lb, lh, lw, lbu, lhu, sb, sh, sw
beq, bne, blt, bge, bltu, bgeu
jal, jalr, lui, auipc
```

The regression also verifies architectural corner behavior such as `x0` write
protection, all 12 branch kind × taken/not-taken combinations in both
directions, byte/halfword write strobes on every lane, signed and unsigned
load extension with real (non-zero) data, jump redirects, and upper
immediates.

System and environment instructions such as `fence`, `ecall`, and `ebreak`
are not part of this milestone. The decoder's `ecall`/`ebreak` trap flags are
assertion-guarded against spurious assertion, but the instructions themselves
are deferred until the project has a trap/exception model. The most
instructive bugs found on the way — including two RTL bugs that survived
fully green regressions — are documented in
[docs/10_bug_case_library.md](docs/10_bug_case_library.md).

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
- [x] Constrained-random program generator with structured streams and seed reproduction
- [x] In-testbench ISS reference model in lockstep with the RTL
- [x] Concurrent assertion set (15 properties) with failure-count regression gating
- [x] Functional coverage model (instruction, memory, control-flow) closed to 100% of defined bins
- [x] Code coverage collection scoped to the core with documented exclusions
- [ ] Commit/retire monitor for pipeline-friendly checking
- [ ] Five-stage pipeline implementation
- [ ] Forwarding, hazard detection, stalls, and flushes

## Verification Summary

Primary regression (VCS):

```sh
make run                          # 200-seed constrained-random regression
make cov                          # same regression with coverage collection
python3 scripts/parse_cov.py      # coverage report with per-bin holes
```

Validated v0.4.0 result:

```text
SUMMARY: 200 passed, 0 failed
ASSERTION FAILURES: 0
ALL RANDOM TESTS PASSED
RV_INSTR_COVERAGE  = 100.00%
RV_MEM_COVERAGE    = 100.00%
RV_BRANCH_COVERAGE = 100.00%
```

Every seed is checked on three axes: the full memory transaction stream
(direction, address, strobes, masked data), the final register file
`x1..x31`, and retire count/final PC — all against the ISS. A failing seed
prints its `+SINGLE_SEED` reproduction command. Density and assertion-count
guards keep the regression from passing vacuously.

The v0.3.0 directed assembly suite is retained as the end-to-end smoke
baseline (`./scripts/asm_to_hex.sh && ./tools/rv32i_ref.py --all`):

| Test | Main coverage | Checker style |
|---|---|---|
| `x0_test` | Writes to `x0` ignored, reads from `x0` return zero | memory transactions + final signatures |
| `alu_itype_test` | ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI | memory transactions + final signatures |
| `alu_rtype_test` | ADD/SUB/AND/OR/XOR/SLT/SLTU/SLL/SRL/SRA | memory transactions + final signatures |
| `load_store_width_test` | SB/SH/SW/LB/LBU/LH/LHU, byte masks, signedness | memory transactions + final signatures |
| `branch_matrix_test` | BEQ/BNE/BLT/BGE/BLTU/BGEU taken and not-taken | memory transactions + final signatures |
| `jump_u_type_test` | LUI/AUIPC/JAL/JALR redirect and writeback behavior | memory transactions + final signatures |

## Verification Architecture

The v0.4.0 random flow is self-contained in SystemVerilog:

```text
rv_program.build(seed)                 constrained-random structured program
  -> rv_instr.encode()                 instruction encoding
  -> core_memory_model.imem            shared instruction image
  -> rv_ref_model.run_iss()            ISS: expected txns / regs / retire
  -> core_single_cycle (DUT)           executes the same image
  -> core_monitor                      observed memory transactions
  -> core_scoreboard                   txn stream + regfile + retire checks
  -> core_assertions                   15 properties, failure-count gated
  -> rv_coverage                       execution-side functional coverage
```

The v0.3.0 directed assembly flow
(`programs/asm -> asm_to_hex.sh -> tools/rv32i_ref.py -> expected files`)
is kept beside it as the smoke baseline.

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
| `tb/sv/core/core_scoreboard.sv` | Transaction-stream, register-file, and retire checks |
| `tb/sv/core/core_assertions.sv` | 15 concurrent properties; failures gate the regression verdict |
| `tb/sv/core/random/rv_random_pkg.sv` | Random subsystem package: instruction kinds and encoders |
| `tb/sv/core/random/rv_instr.sv` | Randomizable instruction class with legality/safety constraints |
| `tb/sv/core/random/rv_program.sv` | Structured program generator: loops, branches, JALR, store→load pairs |
| `tb/sv/core/random/rv_ref_model.sv` | ISS reference model (fatals on anything it does not implement) |
| `tb/sv/core/random/rv_coverage.sv` | Execution-side functional coverage (instruction/memory/control-flow) |
| `tb/filelists/core_sv.f` | VCS compile filelist |
| `tb/filelists/cm_hier.config` | Restricts code coverage collection to the core |
| `scripts/parse_cov.py` | Coverage-database report: per-module metrics and zero-hit bins |
| `programs/asm/` | Directed assembly tests |
| `programs/hex/` | Generated instruction-memory images |
| `programs/expected/` | Generated expected `TXN` and `SIG` files |
| `tools/rv32i_ref.py` | Small repository-specific RV32I reference model |
| `docs/` | Architecture, ISA, verification, and milestone notes |

The architecture is deliberately pipeline-ready: the generator, ISS, and
scoreboard are independent of the core's microarchitecture. Moving to the
five-stage pipeline mainly means replacing the monitor's single-cycle bus
view with a commit/retire view.

## Running The Project

Build and run the constrained-random regression:

```sh
make run                              # 200 seeds
make run ARGS="+SINGLE_SEED=<n>"      # reproduce one failing seed
make run ARGS="+NUM_SEEDS=<n>"        # change regression size
```

Run with coverage and report it:

```sh
make cov
python3 scripts/parse_cov.py
```

Compile only:

```sh
make build
```

The `Makefile` builds `core_sv_tb` from `tb/filelists/core_sv.f` and writes
simulation output and the coverage database under `sim/build/core_vcs/`.
Directed assembly programs can be regenerated with `./scripts/asm_to_hex.sh`
and their expected files with `./tools/rv32i_ref.py --all`.

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
├── scripts/
├── tb/
│   ├── filelists/
│   └── sv/core/
├── tools/
└── sim/
```

## Known Limitations

Documented in detail in
[docs/09_v0_4_0_milestone.md](docs/09_v0_4_0_milestone.md); the short list:

- `fence`, `ecall`, `ebreak`, privileged behavior, traps, interrupts, CSRs,
  and real bus wait states are out of scope. The `ecall`/`ebreak` decoder
  flags are assertion-guarded against spurious assertion, but the
  instructions are never executed.
- Illegal-instruction decode paths are not error-injected; random programs
  contain only legal encodings.
- Loads/stores are constrained to a safe, aligned data window: non-zero base
  registers, negative offsets, and misalignment are deferred to the pipeline
  phase.
- A few composed corners are not directly stimulated (JALR targets with bit 0
  set, `JAL` with `rd != x0`, `BGE`/`BGEU` with equal operands); the
  underlying datapaths are covered through neighboring instructions.
- The ISS in `rv_ref_model.sv` implements exactly the supported subset and
  fatals on anything else — it is an oracle for this project, not a full
  architectural simulator.
- The pipeline files under `rtl/pipeline/` are placeholders for the next
  phase, not a verified five-stage implementation.

## Roadmap

1. Implement the five-stage pipeline: IF, ID, EX, MEM, WB.
2. Add a commit/retire monitor so the existing generator, ISS, and scoreboard
   carry over unchanged from the single-cycle bus view.
3. Add forwarding, load-use stall handling, and branch flushes, with
   pipeline-focused directed and random regressions.
4. Open up the memory stimulus: non-zero base registers, negative offsets,
   and (with a defined trap model) misalignment and error injection.
5. Move toward a ready/valid memory interface and, later, caches and a small
   SoC fabric.
