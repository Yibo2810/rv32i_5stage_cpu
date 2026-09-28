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
list. The design is not synthesized yet. See
[11_v0_5_0_milestone.md](11_v0_5_0_milestone.md),
[03_pipeline_design.md](03_pipeline_design.md) and
[04_hazard_forwarding.md](04_hazard_forwarding.md).

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
| 13 | v0.6.0 FPGA bring-up: synthesis, LUTRAM instruction memory, block-RAM data memory, pass/fail on an LED or UART TX | **Next** |
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
make pl-run ARGS="+NUM_SEEDS=500 +SEED_OFFSET=1"
make pl-lint                                             # Verilator -Wall lint
```

Validated v0.5.0 evidence:

```text
SUMMARY: 500 passed, 0 failed
ASSERTION FAILURES: 0
PIPELINE SVA FAILURES: 0
ALL RANDOM TESTS PASSED
PIPE_FWD_COVERAGE = 100.00%, PIPE_LU_COVERAGE = 87.00%, PIPE_REDIR_COVERAGE = 86.05%
```

Logs land in `sim/build/pipeline_vcs/run.log`.

## Immediate Next Work

v0.6.0, FPGA bring-up. The frozen v0.5.0 regression gates any change to the
core.

1. Synthesize `core_5stage`; confirm block-RAM inference for `dmem_bram` and
   LUTRAM inference for a combinational-read instruction memory.
2. Add a board top level: clock, reset synchronization, instruction-memory
   initialization, and a pass/fail output (LED or UART TX).
3. Run a self-checking program on the board.

After that, v0.7.0 moves instruction fetch to a request/response interface so
the instruction memory can live in block RAM, and adds a memory model with
back-pressure.
