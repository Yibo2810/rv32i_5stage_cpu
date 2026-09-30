# RV32I 5-Stage CPU

A learning-oriented RV32I CPU project implemented in Verilog and
SystemVerilog.

The project has completed its **v0.6.0 milestone: the pipeline running on an
FPGA board**. On a Digilent Arty A7-100T at 25 MHz, a directed hazard program
with a self-checking tail runs on the core and reports PASS on the board LEDs
(board smoke test, passing case only). See
[docs/12_v0_6_0_milestone.md](docs/12_v0_6_0_milestone.md).

The core is the **v0.5.0 five-stage pipeline, verified in simulation**, and
is functionally unchanged on the board. The pipelined core (IF/ID/EX/MEM/WB, forwarding,
load-use stalls, redirect flushes, a global freeze on memory stalls, a
WB-committed exception token, and a request/response data-memory interface) is
checked by a seed-reproducible constrained-random regression: every retired
instruction is compared against an in-testbench ISS, interface-level and
white-box assertions gate the verdict, and a microarchitectural coverage model
measures which forwarding, stall and redirect situations the stimulus reached.
See [docs/11_v0_5_0_milestone.md](docs/11_v0_5_0_milestone.md),
[docs/03_pipeline_design.md](docs/03_pipeline_design.md) and
[docs/04_hazard_forwarding.md](docs/04_hazard_forwarding.md).

The single-cycle core verified in **v0.4.0** stays in the tree as the frozen
baseline, and its regression still passes on the current tree.

## Current Milestone

**v0.6.0: FPGA bring-up on an Arty A7-100T — board smoke test passed**
(see [docs/12_v0_6_0_milestone.md](docs/12_v0_6_0_milestone.md))

The frozen pipeline sits in a portable system wrapper (`fpga_sys`: an
instruction ROM in LUTs, the block-RAM data memory, a trap latch and a `tohost`
store observer) and a board wrapper (`arty_a7_top`: MMCM 100 → 25 MHz, reset
synchronizer, LED views). `hazard_test` compares its own 15 signature words and
writes a verdict to `tohost` (`0x3FC`); the wrapper turns it into PASS/FAIL.
The program passes on `fpga_sys` in VCS and on the board. Vivado reports
WNS +21.9 ns at 25 MHz, 1750 LUTs, 1641 flip-flops and one RAMB18. The fail
path has not been exercised yet, in simulation or on the board.

**v0.5.0 (frozen): five-stage pipeline, verified in simulation**
(see [docs/11_v0_5_0_milestone.md](docs/11_v0_5_0_milestone.md))

Each seed runs the same structured random program on the pipeline and on the
ISS and compares every retired instruction (PC, instruction, next PC and, when
it writes one, the destination register and value), the memory transaction
stream, the retire count/final PC, and the final register file. The stimulus
adds pipeline pressure on top of the v0.4.0 templates: a bias that makes
instructions read the destinations of the previous one to three instructions,
branch and `JALR` operands that come from loads, stores placed right before a
redirect, and memory accesses whose base register is forwarded or itself
loaded. Instruction fetch is combinational, so on an FPGA the instruction
memory is an asynchronous-read memory in LUTs, not block RAM (synthesized in
v0.6.0).

**v0.4.0 (frozen): constrained-random verification of the single-cycle core**
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
- [x] Commit/retire monitor for pipeline-friendly checking (`tb/sv/pipeline/pipeline_monitor.sv`)
- [x] Five-stage pipeline RTL: IF, ID, EX, MEM, WB with per-stage enable/flush
- [x] Forwarding (EX/MEM, MEM/WB, WB→ID bypass), load-use stall, redirect flush, global freeze on memory stall
- [x] Unified exception token (`exception_t`) committed at WB, with sticky `halted`
- [x] Request/response data-memory interface (single outstanding) plus a BRAM adapter
- [x] Pipeline constrained-random regression with ISS lockstep on the commit stream (per-instruction comparison)
- [x] Pipeline interface assertions (11) and white-box assertions bound into the core (13), gating the verdict per seed
- [x] Pipeline functional coverage: ISA covergroups at retirement plus forwarding / load-use / redirect covergroups
- [x] Mutation check: four injected pipeline bugs each fail the regression
- [x] Directed pipeline hazard test (`hazard_test.S`: load-use, forwarding and redirect cases) with a self-checking tail
- [x] Vivado synthesis and implementation for an Arty A7-100T (25 MHz, timing met)
- [x] Board smoke test: the self-checking `hazard_test` reports PASS on the board LEDs
- [ ] Fail-path (negative) test in simulation and on the board
- [ ] On-board debug visibility (ILA or UART)
- [ ] Request back-pressure stimulus

## Verification Summary

FPGA bring-up (v0.6.0): `fpga_sys` in VCS, then the Arty A7-100T:

```text
SUMMARY cycles=206 timeout=0 halted=1 cause=EXC_BREAKPOINT trap_pc=00000240
SUMMARY tohost_seen=1 tohost=00000001 pass=1 fail=0 error_trap=0 mark_seen=1
FPGA_SYS PASS
Vivado (xc7a100tcsg324-1, 25 MHz): WNS +21.925 ns, WHS +0.162 ns, 1750 LUT, 1641 FF, 1 RAMB18
Board: PASS LED on, all four LED views as expected
```

Only the passing case has been run; the fail path is still open. Details and
the LED map: [docs/12_v0_6_0_milestone.md](docs/12_v0_6_0_milestone.md).

Pipeline regression (v0.5.0), 500 seeds with a fixed seed offset:

```sh
make pl-build
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500 -l sim/build/pipeline_vcs/run.log
```

`make pl-run` places a time-based `+SEED_OFFSET` in front of `$(ARGS)` and the
testbench takes the first match, so a fixed offset has to be passed to `simv`
directly. Re-run with offset 1 on the v0.6.0 tree (2026-09-30), the result is
identical to the v0.5.0 release below (`total_txns=5688`,
`total_retired=29676`, same coverage).

Validated v0.5.0 result:

```text
SUMMARY: 500 passed, 0 failed
ASSERTION FAILURES: 0
PIPELINE SVA FAILURES: 0
ALL RANDOM TESTS PASSED
RV_INSTR_COVERAGE   = 100.00%
RV_MEM_COVERAGE     = 100.00%
RV_BRANCH_COVERAGE  = 100.00%
PIPE_FWD_COVERAGE   = 100.00%
PIPE_LU_COVERAGE    =  87.00%   (remaining bins waived)
PIPE_REDIR_COVERAGE =  86.05%   (remaining bins waived)
```

The waived bins, the two bins that are unreachable by design, and the mutation
results are listed in [docs/11_v0_5_0_milestone.md](docs/11_v0_5_0_milestone.md).

Single-cycle regression (VCS):

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

The v0.5.0 pipeline flow reuses the same structure on the commit stream:

```text
pl_program.build(seed)                 structured program + hazard bias + pipeline templates
  -> pipeline_memory.imem              program image, EBREAK everywhere after it
  -> pl_ref_model.run_iss()            ISS: expected commits / txns / regs / final PC
  -> core_5stage (DUT)                 executes the same image
  -> pipeline_monitor                  retired instructions + memory transactions
  -> pipeline_scoreboard               commit stream + txn stream + retire + regfile
  -> pipeline_assertions               11 interface properties, gated
  -> pipeline_sva_bind (bind)          13 white-box properties, gated per seed;
                                       forwarding / load-use / redirect covergroups
  -> pl_coverage                       ISA coverage sampled at retirement
```

Important files:

| Path | Role |
|---|---|
| `rtl/include/single_pkg.sv` | Shared SystemVerilog RV32I constants and control types |
| `rtl/single_cycle/` | Current verified single-cycle CPU RTL |
| `rtl/pipeline/` | Five-stage pipeline RTL: `{if,id,ex,mem,wb}_stage.sv`, `pipeline_regs.sv`, `hazard_unit.sv`, `forwarding_unit.sv`, `core_5stage.sv`, `memory/dmem_bram.sv` (see [docs/03_pipeline_design.md](docs/03_pipeline_design.md)) |
| `rtl/fpga/rtl/` | Portable FPGA system: `imem_rom.sv` (instruction ROM, combinational read) and `fpga_sys.sv` (core + memories + trap latch + `tohost` observer + pass/fail) |
| `rtl/fpga/arty_a7/` | Arty A7-100T board wrapper (`arty_a7_top.sv`: MMCM, reset synchronizer, LED views) and pin constraints (`arty_a7.xdc`) |
| `rtl/fpga/tb/fpga_sys_tb.sv` | VCS testbench for `fpga_sys`: backdoor program load (`+MEM=`), run to halt, verdict checks (`+EXPECT_TOHOST=`) |
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
| `tb/filelists/core_sv.f` | VCS compile filelist (single-cycle) |
| `tb/sv/pipeline/pipeline_tb.sv` | Pipeline testbench: bring-up smoke program, then the constrained-random seed loop with four checks and assertion gating |
| `tb/sv/pipeline/pipeline_probe_if.sv` | Pipeline interface with `pl_core`/`bram`/`pipeline_monitor` modports |
| `tb/sv/pipeline/pipeline_memory.sv` | Pipeline memory: imem pre-filled with `ebreak` (termination) + `dmem_bram` instance, cleared per seed |
| `tb/sv/pipeline/pipeline_monitor.sv` | Passive capture of commits, memory transactions, and trap events |
| `tb/sv/pipeline/pipeline_scoreboard.sv` | Commit-stream, transaction-stream, retire, and register-file checks |
| `tb/sv/pipeline/pipeline_assertions.sv` | 11 interface properties; failures gate the regression verdict |
| `tb/sv/pipeline/pipeline_sva_bind.sv` | 13 white-box properties bound into `core_5stage`, plus forwarding / load-use / redirect covergroups |
| `tb/sv/pipeline/random/` | Pipeline random subsystem: `pl_instr`, `pl_program` (hazard bias, pipeline templates), `pl_ref_model` (ISS), `pl_coverage` |
| `tb/filelists/pipeline.f` | VCS compile filelist (pipeline) |
| `tb/filelists/pipeline_rtl.f` | Pipeline RTL compile order, shared by lint and VCS |
| `tb/filelists/cm_hier.config` | Restricts code coverage collection to the core |
| `scripts/cov_report.py` | Coverage-database report read directly from the database: per-metric totals and zero-hit bins (`scripts/parse_cov.py` forwards to it) |
| `programs/asm/` | Directed assembly tests |
| `programs/hex/` | Generated instruction-memory images |
| `programs/expected/` | Generated expected `TXN` and `SIG` files |
| `tools/rv32i_ref.py` | Small repository-specific RV32I reference model |
| `docs/` | Architecture, ISA, verification, and milestone notes |

The generator, ISS, and scoreboard are independent of the core's
microarchitecture; the v0.5.0 port kept them and moved the checks onto the
pipeline's commit stream.

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

Run the five-stage pipeline regression:

```sh
make pl-run                                          # 30 seeds, time-based seed offset
make pl-run ARGS="+NUM_SEEDS=500"                    # 500 seeds, time-based seed offset
make pl-run ARGS="+SINGLE_SEED=<n>"                  # reproduce one failing seed
make pl-lint                                         # Verilator -Wall lint of the pipeline RTL
make pl-build                                        # compile only
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500 -l sim/build/pipeline_vcs/run.log   # fixed offset, after pl-build
```

Output is written under `sim/build/pipeline_vcs/` (`compile.log`, `run.log`).
Each run first executes one directed smoke program (`+HEX=...`, default
`load_store_width_test`), then the random seeds. The end of `run.log` holds the
regression summary, the white-box assertion table, the event counts behind each
assertion, and the coverage lines.

Build the FPGA program image and simulate the FPGA system wrapper (v0.6.0),
from the repository root:

```sh
./scripts/asm_to_hex.sh hazard_test && ./tools/rv32i_ref.py hazard_test
mkdir -p rtl/fpga/build
awk -v N=256 'NF {print; n++} END {if (n > N) {print "too big: " n > "/dev/stderr"; exit 1} for (; n < N; n++) print "00100073"}' \
    programs/hex/hazard_test.hex > rtl/fpga/build/hazard_test.mem
mkdir -p sim/build/fpga_sys_vcs/csrc
vcs -full64 -sverilog -debug_access+all -top fpga_sys_tb \
    -f tb/filelists/pipeline_rtl.f \
    rtl/fpga/rtl/imem_rom.sv rtl/fpga/rtl/fpga_sys.sv rtl/fpga/tb/fpga_sys_tb.sv \
    -Mdir=sim/build/fpga_sys_vcs/csrc -o sim/build/fpga_sys_vcs/simv \
    -l sim/build/fpga_sys_vcs/compile.log
./sim/build/fpga_sys_vcs/simv +MEM=rtl/fpga/build/hazard_test.mem -l sim/build/fpga_sys_vcs/run.log
```

The run ends with `FPGA_SYS PASS`. The Vivado steps (project mode,
`xc7a100tcsg324-1`) and the LED map are in
[docs/12_v0_6_0_milestone.md](docs/12_v0_6_0_milestone.md).

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
│   ├── fpga/
│   │   ├── arty_a7/
│   │   ├── rtl/
│   │   └── tb/
│   ├── include/
│   ├── pipeline/
│   │   └── memory/
│   └── single_cycle/
├── scripts/
├── tb/
│   ├── filelists/
│   └── sv/
│       ├── core/
│       │   └── random/
│       └── pipeline/
│           └── random/
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
- Loads/stores are constrained to a safe, aligned data window. The v0.5.0
  pipeline flow adds non-zero base registers (forwarded or loaded); negative
  offsets and misalignment remain out of scope.
- A few composed corners are not directly stimulated (JALR targets with bit 0
  set, `JAL` with `rd != x0`, `BGE`/`BGEU` with equal operands); the
  underlying datapaths are covered through neighboring instructions.
- The ISS in `rv_ref_model.sv` implements exactly the supported subset and
  fatals on anything else — it is an oracle for this project, not a full
  architectural simulator.
- On hardware, only one directed self-checking program has run (v0.6.0), and
  only its passing case; the random regression runs in simulation only.
  Instruction fetch is a same-cycle combinational read, so the instruction
  memory is a ROM in LUTs, not block RAM. FPGA-specific limitations (no
  negative test yet, no on-board debug visibility, GUI-only Vivado build) are
  listed in [docs/12_v0_6_0_milestone.md](docs/12_v0_6_0_milestone.md).
- The pipeline's data memory is single-outstanding with a 2-cycle cost per
  load/store against a 1-cycle BRAM; the testbench memory never applies
  back-pressure.
- Trap handling in the pipeline is "flush everything younger, then halt
  forever" (`halted`); only the terminating `ebreak` is exercised, and there is
  no CSR, `mtvec`, `mepc`, `mcause` or `mtval`, and no exception return.
- Pipeline coverage is closed except for an enumerated waiver list, and the ISS
  is not yet cross-checked against an external reference (riscv-arch-test,
  Spike or Sail). Details: [docs/11_v0_5_0_milestone.md](docs/11_v0_5_0_milestone.md).

## Roadmap

1. ~~Implement the five-stage pipeline: IF, ID, EX, MEM, WB.~~ **Done (v0.5.0).**
2. ~~Add forwarding, load-use stall handling, branch flushes, and a
   request/response data-memory interface.~~ **Done (v0.5.0).**
3. ~~Port the constrained-random regression to the pipeline's commit stream,
   with assertions and coverage.~~ **Done (v0.5.0), verified in simulation.**
4. ~~v0.6.0 — FPGA bring-up: synthesis, LUT-based instruction memory,
   block-RAM data memory, top-level wrapper with clock and reset
   synchronization, pass/fail on LEDs.~~ **Done (v0.6.0): board smoke test
   passed on an Arty A7-100T.** Still open: the fail-path test, on-board debug
   visibility (ILA or UART), a scripted Vivado build.
5. **v0.7.0 — request/response instruction fetch**, so the instruction memory
   can live in block RAM, plus a data memory model with back-pressure.
6. Peripherals on a bus (UART, timer), interrupts with CSRs and trap handling,
   caches, external memory; an external ISA reference (riscv-arch-test, Spike
   or Sail).
