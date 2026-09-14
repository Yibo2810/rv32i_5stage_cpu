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

Two things are true at the same time, and the difference matters:

**v0.4.0 — the single-cycle core is frozen and verified.** A seed-reproducible
constrained-random regression runs the RTL and an in-testbench ISS in lockstep,
checking the memory transaction stream, the register file, and the retire
count/final PC, gated by concurrent assertions and closed functional coverage.
See [09_v0_4_0_milestone.md](09_v0_4_0_milestone.md). This claim needs a fresh
`make run` before it is repeated, because `control_unit`, `load_store_unit` and
`core_single_cycle` were edited while landing the pipeline.

**v0.5.0 (in progress) — the five-stage pipeline exists in RTL and is in
bring-up.** IF/ID/EX/MEM/WB are implemented together with forwarding, load-use
stalls, redirect flushes, a global freeze on memory stalls, a unified exception
token committed at WB, and a request/response data-memory interface with a BRAM
adapter for the FPGA build. Verification so far is directed only: six assembly
programs run through the pipeline and must halt on a single `ebreak` trap; the
testbench still has no built-in oracle, and the constrained-random flow has not
been ported to the pipeline yet. See
[03_pipeline_design.md](03_pipeline_design.md),
[04_hazard_forwarding.md](04_hazard_forwarding.md) and
[11_v0_5_0_pipeline_bringup.md](11_v0_5_0_pipeline_bringup.md).

Nothing about the pipeline is *verified* yet; "implemented", "bring-up
exercised" and "verified" are kept strictly apart in the documentation.

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
| 9 | Five-stage pipeline partitioning (IF/ID/EX/MEM/WB) | RTL complete, directed bring-up only |
| 10 | Forwarding, hazard detection, load-use stalls, branch flushes | RTL complete, directed bring-up only |
| 11 | Ready/valid memory interface (single outstanding, 2-cycle load/store) and BRAM adapter | RTL complete, bring-up exercised, not verified |
| 12 | Pipeline verification: oracle-driven directed tests, hazard/hazard-stress tests, random regression, coverage closure | **In progress — next** |
| 13 | FPGA bring-up: synthesis, BRAM/LUTRAM inference check, `halted` on an LED, board test | Planned |

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

Five-stage pipeline bring-up (v0.5.0, directed only):

```sh
make pl-lint                                             # Verilator -Wall lint
make pl-run ARGS="+HEX=programs/hex/load_store_width_test.hex"
make pl-run ARGS="+HEX=programs/hex/branch_matrix_test.hex"
```

Verdict today: `BRINGUP DONE` on "no timeout and exactly one `EXC_BREAKPOINT`
trap". Logs land in `sim/build/pipeline_vcs/run.log`.

## Immediate Next Work

1. Commit the pipeline working tree (exception token / memory protocol / BRAM
   adapter / testbench bring-up as separate commits).
2. Re-run the single-cycle `make run` regression and re-confirm the v0.4.0
   baseline under the shared-module edits.
3. Give the pipeline testbench an oracle: adapt the scoreboard to the
   retire/transaction view and check `programs/expected/*.expected` (transaction
   stream + final signatures) inside the testbench instead of by hand.
4. Add pipeline assertions for the invariants listed in
   `03_pipeline_design.md` §7 and `04_hazard_forwarding.md` §7.
5. Write the missing directed tests: `hazard_test.S` (currently a stub),
   deliberate forwarding chains, misaligned load/store, illegal instruction,
   `ecall`, and randomised request-channel back-pressure.
6. Port the constrained-random flow (`tb/sv/pipeline/random/`) into the pipeline
   filelist and run the ISS-lockstep regression against the retire view.
7. Then FPGA: Vivado synthesis, confirm BRAM/LUTRAM inference and resource use,
   and bring the pipeline up on the board.
