# Project Plan

## Goals

- Build a credible RV32I CPU project that grows from a verified single-cycle
  core into a classic five-stage pipeline.
- Keep verification self-checking, reproducible, and documented.
- Use directed tests first, then add assertions, functional coverage, and
  constrained-random stimulus.
- Preserve the project as an engineering portfolio artifact with clear release
  milestones.

## Current State

Two frozen milestones sit side by side in the tree:

**v0.4.0 — the single-cycle core is frozen and verified.** A seed-reproducible
constrained-random regression runs the RTL and an in-testbench ISS in lockstep,
checking the memory transaction stream, the register file, and the retire
count/final PC, gated by concurrent assertions and closed functional coverage.
See [09_v0_4_0_milestone.md](09_v0_4_0_milestone.md). The shared leaf modules
(`control_unit`, `load_store_unit`, `core_single_cycle`) were edited while
landing the pipeline; the regression was re-run on the v0.5.0 tree and still
passes (200 seeds, zero assertion failures, 100% of defined coverage bins).

**v0.5.0 — the five-stage pipeline is frozen and verified in simulation.**
IF/ID/EX/MEM/WB with forwarding, load-use stalls, redirect flushes, a global
freeze on memory stalls, a unified exception token committed at WB, and a
request/response data-memory interface. The constrained-random regression runs
the pipeline and the ISS in lockstep and compares every retired instruction,
the memory transaction stream, the retire count/final PC and the register file;
interface-level and white-box assertions gate the verdict, and a forwarding /
load-use / redirect coverage model is closed except for an enumerated waiver
list. See
[11_v0_5_0_milestone.md](11_v0_5_0_milestone.md),
[03_pipeline_design.md](03_pipeline_design.md) and
[04_hazard_forwarding.md](04_hazard_forwarding.md).

**v0.6.0 — the pipeline runs on an FPGA board (smoke test).** On a Digilent
Arty A7-100T at 25 MHz, the functionally unchanged v0.5.0 core runs the
directed `hazard_test` with a self-checking tail and reports PASS on the board
LEDs. A portable wrapper (`fpga_sys`: instruction ROM in LUTs, block-RAM data
memory, trap latch, `tohost` observer, pass/fail) is simulated in VCS with the
same program; a board wrapper adds the MMCM, a reset synchronizer and LED
views. Timing is met with WNS +21.9 ns. Only the passing case has been run.
See [12_v0_6_0_milestone.md](12_v0_6_0_milestone.md).

"Implemented", "verified in simulation" and "running on hardware" are kept
strictly apart in the documentation.

## Milestones

| Phase | Milestone | Status |
|---|---|---|
| 0 | Repository structure and documentation scaffold | Done |
| 1 | Minimal single-cycle RTL modules | Done |
| 2 | Basic assembly-to-hex and signature tests | Done |
| 3 | v0.1 minimal single-cycle smoke regression | Done |
| 4 | v0.2.0 SystemVerilog R/I direct module-path verification | Done |
| 5 | Expanded single-cycle datapath for branches, jumps, U-type, and load/store widths | Done |
| 6 | v0.3.0 VCS core-level directed verification architecture | Done |
| 7 | Assertions and lightweight functional coverage | Done (shipped inside v0.4.0) |
| 8 | Constrained-random program generation with ISS reference | Done (v0.4.0 freeze) |
| 9 | Five-stage pipeline partitioning (IF/ID/EX/MEM/WB) | Done (v0.5.0 freeze) |
| 10 | Forwarding, hazard detection, load-use stalls, branch flushes | Done (v0.5.0 freeze) |
| 11 | Request/response data-memory interface (single outstanding, 2-cycle load/store) and BRAM adapter | Done (v0.5.0 freeze); back-pressure not exercised |
| 12 | Pipeline verification: ISS-lockstep random regression on the commit stream, assertions, coverage | Done (v0.5.0 freeze) |
| 13 | v0.6.0 FPGA bring-up: synthesis, LUT-based instruction ROM, block-RAM data memory, self-checking program with pass/fail on LEDs | Done (board smoke test on an Arty A7-100T, passing case only); negative test and on-board debug visibility open |
| 14 | v0.7.0 Request/response instruction fetch (instruction memory in block RAM), back-pressure memory model | Planned |

## Current Release Commands

Frozen single-cycle regression (v0.4.0):

```sh
./scripts/asm_to_hex.sh
./tools/rv32i_ref.py --all
make run
```

Validated v0.4.0 evidence:

```text
SUMMARY: 200 passed, 0 failed
ASSERTION FAILURES: 0
ALL RANDOM TESTS PASSED
```

Frozen pipeline regression (v0.5.0):

```sh
make pl-build
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500 -l sim/build/pipeline_vcs/run.log
make pl-lint                                             # Verilator -Wall lint
```

`make pl-run ARGS="+SEED_OFFSET=..."` does not set the offset: the Makefile
passes a time-based `+SEED_OFFSET` first and the testbench takes the first
match. Re-run with offset 1 on the v0.6.0 tree (2026-09-30): identical to the
v0.5.0 release (`total_txns=5688`, `total_retired=29676`, same coverage,
0 assertion and 0 white-box failures).

Validated v0.5.0 evidence:

```text
SUMMARY: 500 passed, 0 failed
ASSERTION FAILURES: 0
PIPELINE SVA FAILURES: 0
ALL RANDOM TESTS PASSED
PIPE_FWD_COVERAGE = 100.00%, PIPE_LU_COVERAGE = 87.00%, PIPE_REDIR_COVERAGE = 86.05%
```

Logs land in `sim/build/pipeline_vcs/run.log`.

FPGA system wrapper (v0.6.0), program image and simulation: see
[12_v0_6_0_milestone.md](12_v0_6_0_milestone.md) §8. Validated v0.6.0
evidence:

```text
FPGA_SYS PASS          cycles=206, trap_pc=00000240, tohost=00000001, cause=EXC_BREAKPOINT
Vivado, 25 MHz         WNS +21.925 ns, WHS +0.162 ns, 1750 LUT, 1641 FF, 1 RAMB18
Arty A7-100T           PASS LED on, all four LED views as expected
```

## Immediate Next Work

Finish v0.6.0. The frozen v0.5.0 regression still gates any change to the
core.

1. Negative tests: a corrupted-constant program must fail in `fpga_sys_tb`
   (`+EXPECT_TOHOST=7`) and on the board (FAIL at check 3 on the LEDs).
2. Testbench checks for `fail`, `error_trap` and `tohost_seen`; Makefile
   targets for the program image and the `fpga_sys` simulation.
3. A scripted, non-project Vivado build in the repository.
4. On-board visibility: an HDL-instantiated ILA or a UART TX.

After that, v0.7.0 moves instruction fetch to a request/response interface so
the instruction memory can live in block RAM, and adds a memory model with
back-pressure.
