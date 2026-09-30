# v0.5.0 Milestone: Five-Stage Pipeline Verification Freeze

## Summary

v0.5.0 freezes the five-stage RV32I pipeline (`core_5stage`) and its
verification environment.

The pipeline implements IF/ID/EX/MEM/WB with EX/MEM and MEM/WB forwarding, a
WB→ID register-file bypass, a one-bubble load-use stall, EX-stage branch/jump
resolution with a two-slot flush, a global freeze on memory stalls, a unified
exception token committed at WB, and a single-outstanding request/response data
memory interface.

It is verified in simulation by the constrained-random flow carried over from
v0.4.0 and rebuilt around the pipeline's commit stream: every seed runs the same
program on the RTL and on an in-testbench ISS, and every retired instruction is
compared one by one. Two assertion layers (interface-level and white-box via
`bind`) gate the verdict, and a microarchitectural coverage model measures which
forwarding, stall and redirect situations the stimulus actually reached.

Validated release result (500-seed regression, `+SEED_OFFSET=1`):

```text
SUMMARY: 500 passed, 0 failed | total_txns=5688, total_retired=29676
ASSERTION FAILURES: 0
PIPELINE SVA FAILURES: 0
ALL RANDOM TESTS PASSED
RV_INSTR_COVERAGE  = 100.00%
RV_OPCODE_COVERAGE = 100.00%
RV_KIND_COVERAGE   = 100.00%
RV_MEM_COVERAGE    = 100.00%
RV_BRANCH_COVERAGE = 100.00%
PIPE_FWD_COVERAGE   = 100.00%
PIPE_LU_COVERAGE    = 87.00%     (remaining bins waived, see §5.3)
PIPE_REDIR_COVERAGE = 86.05%     (remaining bins waived, see §5.3)
```

A time-seeded run (`make pl-run`, 30 seeds) also passed with zero assertion
failures. The frozen single-cycle regression was re-run on the same tree after
the shared leaf modules were edited for the pipeline, and still passes:

```text
SUMMARY: 200 passed, 0 failed | total_txns=1896, total_retired=11906
ASSERTION FAILURES: 0
ALL RANDOM TESTS PASSED
RV_INSTR/OPCODE/KIND/MEM/BRANCH_COVERAGE = 100.00%
```

**Status: verified in simulation at the core boundary**, with functional
coverage closed except for an enumerated waiver list. The design has **not been
synthesized**; see §7.

No functional RTL bug was found by the random regression during this phase —
the only RTL edit since the directed bring-up was a port rename in
`forwarding_unit` (`exmem_reg_read` → `exmem_mem_read`). Every bug found was in
the verification environment (§6). To show that the checkers are not
decoration, four pipeline bugs were injected on purpose and each one fails the
regression (§4.3).

---

## 1. Scope and interface contract

| Area | State |
|---|---|
| IF/ID/EX/MEM/WB partition | `rtl/pipeline/{if,id,ex,mem,wb}_stage.sv`, `pipeline_regs.sv` with per-stage `en`/`flush` |
| Forwarding | EX/MEM and MEM/WB into EX (`forwarding_unit.sv`, EX/MEM has priority), plus a WB→ID bypass in `id_stage` |
| Load-use stall | One bubble (`hazard_unit.sv`), gated by the decoder's `ctrl_uses_rs1/rs2` |
| Redirect | Branches and jumps resolve in EX; IF/ID and ID/EX are flushed (two-slot penalty) |
| Memory stall | Global freeze; one retire rule `wb_retire = memwb_q.valid && !mem_stall` |
| Hazard priority | `trap/halted > mem_stall > redirect > load-use` |
| Exceptions | `exception_t {valid, cause}` committed at WB; a trap flushes all younger work and sets a sticky `halted`; no CSRs |
| Data memory | Single-outstanding `req_valid/req_ready` + `rsp_valid/rsp_ready`; `rtl/pipeline/memory/dmem_bram.sv` answers in one cycle, so every load/store occupies MEM for two cycles |

**Interface contract frozen with this release:**

- **Instruction fetch is combinational**: `imem_rdata` must be valid in the
  same cycle as `imem_addr`. On an FPGA the instruction memory therefore has to
  be an asynchronous-read memory (LUTRAM / distributed RAM). Moving the
  instruction memory to block RAM or to a request/response interface changes
  the IF stage and is a later version.
- The data memory interface is the request/response protocol above; the
  testbench memory never de-asserts `req_ready` (§7).

Design details: [03_pipeline_design.md](03_pipeline_design.md) and
[04_hazard_forwarding.md](04_hazard_forwarding.md).

---

## 2. What the regression is

Each seed:

```text
pl_program.build(seed)          structured random program, 20-40 static instructions
clear_dmem()                    data memory zeroed -> every seed is independent
imem <- EBREAK everywhere       then the program image is overlaid on the first N words
pl_ref_model.run_iss()          zero-time ISS: commits, memory transactions, registers, final PC
core_5stage runs                until halted on the first EBREAK after the program (4000-cycle watchdog)
four checks + no timeout        a failing seed prints make pl-run ARGS="+SINGLE_SEED=<n>"
```

| Check | Compares | Catches |
|---|---|---|
| `check_commits` | every retired instruction: `pc`, `instr`, `next_pc`, `rd_we`, and `rd_addr`/`rd_data` only when `rd_we = 1` | the first diverging instruction, whatever the cause |
| `check` | the memory transaction stream (direction, address, strobes, masked data, load data) | load/store datapath, byte lanes, ordering |
| `check_retire` | retired-instruction count and final PC | extra/missing execution, wrong termination |
| `check_regfile` | final `x1..x31` | accumulated data errors |

Termination is symmetric by construction: the ISS stops *before* executing the
EBREAK, and the monitor drops the retiring instruction that carries an
exception, so neither side counts it.

The ISS executes sequentially and models no pipeline structure. For forwarding,
stall and flush bugs it is therefore an independent implementation of the same
architecture — which is why the commit stream, not any internal pipeline
signal, is the golden comparison point.

---

## 3. Stimulus design

The generator keeps the v0.4.0 design — a weighted choice among templates that
are correct by construction, filled with random straight-line instructions —
and adds pipeline-specific pressure.

| Template (weight) | Content |
|---|---|
| Straight-line (45) | Random ALU/load/store/LUI/AUIPC; **50% hazard bias**: `rs1` (or `rs2` for stores) is taken from the destination of one of the previous three instructions, which lands on EX/MEM forwarding, MEM/WB forwarding or the WB→ID bypass |
| Bounded loop (15) | Counter in `x31`, guard branch, body of straight-line code, `BNE` or `JAL` back edge; generation-time check of the back-edge target |
| Forward branch (25) | Four operand preludes, chosen uniformly: operands set by two `ADDI`s in either order (covers `rs1`←EX/MEM with `rs2`←MEM/WB and the reverse); a store placed immediately before the branch (the redirect must wait for the store's memory stall); an operand stored to memory and loaded back (load-use into the branch comparator) |
| JALR (5) | Target set by `ADDI`, or stored to memory and loaded back (load-use into the jump target) |
| Memory (10) | Store→load pair on the same address, or an address base that is not `x0`: base forwarded from EX/MEM, from MEM/WB, or itself loaded from memory (pointer chasing, load-use into address generation) |

Design rules that kept the stimulus honest:

- The hazard bias is written as implications
  (`!(kind inside {loads, stores}) -> rs1 == c; (kind inside {stores}) -> rs2 == c;`).
  A hard `rs1 == c` does not make randomization fail — the solver silently stops
  choosing loads and stores, which halves load-use coverage.
- Random loads and stores keep `rs1 = x0`, the only register whose value is
  known at generation time. Non-zero bases come only from locked templates that
  compute the address themselves.
- Branch offsets are computed relative to the branch (`(M + 1) * 4`), so preludes
  of any length can be inserted in front of it.

---

## 4. Assertions

### 4.1 Interface layer — `tb/sv/pipeline/pipeline_assertions.sv` (11 properties)

Observe only the instruction/data memory ports and the MEM-stage instruction
(`mem_instr`) through the probe interface: no memory side effects during reset,
aligned and known fetch, read requests carry no write strobes, request fields
known, reads only from loads and writes only from stores, load alignment, store
strobe shape versus width and address. Each failure increments `fail_count` and
prints `$error`; the testbench fails the regression on a non-zero count.

### 4.2 White-box layer — `tb/sv/pipeline/pipeline_sva_bind.sv` (13 properties)

Bound into `core_5stage` with `bind`, so it reads internal signals without
widening the probe interface.

| Property | Checks |
|---|---|
| `pc_stall_assert` | `pc_stall` holds the fetch address |
| `flush_redirect` | an acted redirect flushes IF/ID and ID/EX **in the same cycle** |
| `load_use_assert` | an acted load-use hazard is gone one cycle later |
| `forward_priority_rs{1,2}`, `forward_priority2_rs{1,2}` | forwarding picks a real producer; EX/MEM beats MEM/WB |
| `load_instr_when_stall` | no instruction in EX ever reads the destination of a load sitting in EX/MEM — the *purpose* of the load-use stall, decoded independently from the ISA table |
| `retire_once` | an instruction never retires twice |
| `retire_check` | commit-PC continuity: each retired instruction's `next_pc` equals the PC of the next retired instruction |
| `redirect_valid_assert` | ID always holds a valid instruction when a redirect acts |
| `assume_jump_exmem_bubble`, `assume_jump_memwb_bubble` | while a `JAL`/`JALR` sits in EX/MEM or MEM/WB, EX holds a bubble |

"Acted" means the event survived the hazard priority: load-use and redirect
are only checked in cycles without `mem_stall`, trap or halt. Written without
that gating, the textbook forms fail on this RTL although the RTL is correct
(1516 and 43 false failures in a 200-seed run).

The last three properties are **assumptions about the current design**, not
correctness rules. They document why two coverage bins are unreachable (§5.2)
and will fire when the design changes (for example, branch prediction).

Every failure goes through one `report()` function: per-name counter, total
`fail_count`, `$error`. The testbench compares `u_core.u_sva.fail_count` before
and after every seed, so a white-box failure fails that seed and prints its
reproduction command, and fails the regression at the end.

### 4.3 Mutation check

Four pipeline bugs were injected into copies of the RTL (the repository RTL is
unchanged) and each mutant was run for 30 seeds:

| Mutant | Seeds failed | White-box failures | Assertions that fired |
|---|---|---|---|
| Load-use stall inserts no bubble | 18 / 30 | 131 | `load_instr_when_stall` 88, `retire_check` 25, `retire_once` 18 |
| Retire not gated by the memory stall | 30 / 30 | 558 | `retire_once` 279, `retire_check` 279 |
| Redirect does not flush ID/EX | 30 / 30 | 4967 | `retire_check` 2904, `flush_redirect` 1468, `assume_jump_exmem_bubble` 595 |
| Forwarding priority reversed for `rs1` | 1 / 30 | 4 | `forward_priority2_rs1` 4 |

Every mutant ends in `$fatal`. The table also shows the limits of each checker
kind: `load_use_assert` restates the stall mechanism and stays silent for the
first mutant, while `load_instr_when_stall`, which states the goal, catches it;
`retire_check` catches every control-flow mutant but not the data-only fourth
one. The fourth mutant is triggered in only one seed of thirty: the stimulus,
not the checkers, is the limiting factor for that class of bug.

---

## 5. Coverage

### 5.1 Covergroups

| Group | Sampled | Content |
|---|---|---|
| `cg_instr`, `cg_mem`, `cg_branch` (`pl_coverage.sv`) | at retirement (`retire && !retire_exc`); memory at the request handshake with the MEM-stage instruction | opcode/kind, width × strobe × alignment, branch kind × direction × taken (taken = `retire_next_pc != retire_pc + 4`) |
| `cg_fwd` (bind) | once per instruction, the cycle it leaves EX | `fwd_a × fwd_b`, source × consumer kind, forwarded data source (ALU / load data / link value) |
| `cg_lu` (bind) | the cycle a load-use hazard acts | consumer kind × matching operand, load width × consumer kind |
| `cg_redir` (bind) | the cycle a redirect acts | source (branch/JAL/JALR) × deferred-by-memory-stall, × squashed instruction kind, × operand source |

Two sampling rules matter for correctness of the numbers:

1. Sample once per event, in the cycle the event acts; otherwise frozen cycles
   are counted repeatedly.
2. Count only operands the instruction really reads. `forwarding_unit` compares
   the raw `rs1`/`rs2` bit fields; for a backward `JAL x0` the immediate bits in
   the `rs1` field happen to encode `x31`, which the preceding loop decrement
   has just written, so `fwd_a_sel` reports EX/MEM forwarding for an
   instruction that reads no register. Ungated counts made the
   `fwd_a = EX/MEM × fwd_b = MEM/WB` combination look rare when it had in fact
   never occurred.

Result at 500 seeds:

```text
PIPE_FWD_COVERAGE   = 100.00%   fa=100 fb=100 fa_x_fb=100 fa_x_cons=100 fb_x_cons=100 src_a=100
PIPE_LU_COVERAGE    =  87.00%   cons=100 opnd=100 cons_x_opnd=75.0 ld=100 ld_x_cons=60.0
PIPE_REDIR_COVERAGE =  86.05%   src=100 def=100 kill=75.0 opnd=100 src_x_def=66.7 src_x_kill=75.0 src_x_opnd=85.7
```

Event counts in the same run: 728 acted load-use stalls (257 more cycles where
a load-use hazard waited behind a memory stall), 3820 redirect cycles of which
133 were deferred by a memory stall, 1569 cycles with a jump in EX/MEM, 5701
memory-stall cycles, 29691 retirements.

### 5.2 Unreachable in this design (`ignore_bins`, backed by assertions)

| Bin | Why it cannot occur |
|---|---|
| Forwarding a `JAL`/`JALR` link value (`WB_PC4`) from EX/MEM or MEM/WB | Jumps redirect unconditionally in EX and flush both younger slots; the jump target reads the link value through the WB→ID bypass instead. Backed by `assume_jump_exmem_bubble` / `assume_jump_memwb_bubble`. The `WB_PC4` arm of the forwarding mux becomes reachable once jumps stop flushing (branch prediction). |
| Forwarding load data from EX/MEM | Prevented by the load-use stall; declared `illegal_bins`, never hit |
| A bubble in ID when a redirect acts | IF always supplies a valid instruction; backed by `redirect_valid_assert` |

### 5.3 Waived: reachable, not stimulated in this release

| Bins | Reason the generator does not produce it | Why it is acceptable for this release |
|---|---|---|
| Load-use into a branch's `rs2` or both operands; into both operands of a store | the load-into-branch prelude loads `rs1` only | the MEM/WB-forwarded load value reaches the comparator through the same mux as `rs1`; load→branch `rs1` is covered |
| `LB`/`LH`/`LBU`/`LHU` feeding a branch, a `JALR` or a load address | those templates use `LW` only | sign/zero extension of sub-word loads is covered through ALU and store consumers |
| A redirect that was deferred by a memory stall, for `JAL`/`JALR` | only branches have the store-before-redirect prelude | the deferral logic is shared and is exercised 133 times by branches |
| A branch or jump in the shadow of a taken redirect | the instruction after a branch or jump is never a control-flow instruction | squashing of ALU, load and store instructions (and of the terminating `EBREAK`) is covered; `retire_check` watches continuity |
| `JALR` whose base needs no forwarding | the `JALR` templates always produce the base in the preceding instruction | the no-forwarding operand path is covered by every other instruction class |

### 5.4 Code coverage

Structural (line/branch/condition/toggle) coverage was not collected for the
pipeline in this release. Per-bin functional coverage can be read with
`scripts/cov_report.py`, which parses the simulator's coverage database
directly (`make pl-cov-report`); the percentages quoted above are the ones the
simulator prints at the end of the run.

---

## 6. Bugs found and fixed during this phase

All of them are in the verification environment; the detailed write-ups live in
the project notes, and the recurring patterns are summarized in
[10_bug_case_library.md](10_bug_case_library.md).

| # | Bug | Symptom | Fix |
|---|---|---|---|
| 1 | The random test task was defined but never called | coverage 0% everywhere, bring-up `DONE` with 25 assertion failures in the log | seed loop added; assertion counter gates the verdict |
| 2 | Interface assertions compared MEM-stage requests with the IF-stage instruction | 25 false failures on the bring-up program | use the MEM-stage `mem_instr` |
| 3 | An "exclusive" read/write assertion forbade every store | one false failure per store | replaced by "reads carry no strobes" |
| 4 | Commit comparison included `rd_data` when `rd_we = 0` | 29 of 30 seeds failed; all 294 mismatches were branch/store `rd_data` | compare `rd_addr`/`rd_data` only when `rd_we = 1` |
| 5 | Hazard-bias candidate selection | off-by-one queue index, store/branch `rd` fields (never encoded) used as producers, `if` chain that always picked the oldest candidate | collect legal candidates first, then pick uniformly; `writes_rd()` filter |
| 6 | Hard constraint `rs1 == c` | no error; loads/stores silently disappeared from biased instructions | implication constraints |
| 7 | Textbook assertions used next-cycle flush and ungated load-use | 1516 and 43 false failures | same-cycle check; gate by hazard priority; conclusions on single-cause signals |
| 8 | Template shapes made hazard combinations impossible | redirect during a memory stall, load→branch, load→JALR and non-`x0` address bases never occurred | branch/JALR preludes, memory-base template |
| 9 | White-box assertions did not gate the verdict; counter keys crossed | an `rs1` bug reported as `rs2`; `retire_check` missing from the report | one `report()` path, per-seed and final gating |
| 10 | Ungated forwarding coverage | backward `JAL` counted as forwarding | gate every coverpoint by the operands actually read |

---

## 7. Known limitations (explicitly not verified in v0.5.0)

- **Not synthesized.** No FPGA flow has been run; block-RAM inference for
  `dmem_bram`, LUTRAM inference for the instruction memory, resources and
  timing are all unchecked. The combinational-fetch contract (§1) applies.
- **No memory back-pressure.** The testbench memory never de-asserts
  `req_ready` and always answers in one cycle; request stability under
  back-pressure is designed but unexercised.
- **Trap paths.** Only the terminating `EBREAK` is exercised. Illegal
  instruction, `ecall` and misaligned-access traps are implemented but not
  stimulated, and a trap with a younger store already in MEM (the request
  inhibit path) never occurs. There are no CSRs and no exception return.
- **Coverage waivers** in §5.3.
- **The ISS is written by the same author as the RTL.** It is independent of the
  pipeline structure, but not of the author's reading of the ISA. No external
  reference (riscv-arch-test signatures, Spike or Sail) is used yet.
- **The bring-up smoke run** only checks that the program halts on `EBREAK`; it
  does not require that any instruction retired.
- **CPI is not measured** by the testbench.
- `programs/asm/hazard_test.S` is still a stub; pipeline hazards are covered by
  the random stream instead.
- The hazard bias uses static program order, which differs from execution
  order across taken branches, jumps and loop back edges.
- Verilator `-Wall` lint of the pipeline RTL: 0 errors, 15 warnings
  (`UNUSEDSIGNAL` 4, `EOFNEWLINE` 4, `PINMISSING` 3, `IMPORTSTAR` 3,
  `UNUSEDPARAM` 1).

---

## 8. Running the regression

```sh
make pl-build                                        # compile the pipeline testbench
make pl-run                                          # 30 seeds, time-based seed offset
make pl-run ARGS="+NUM_SEEDS=500 +SEED_OFFSET=1"     # release run
make pl-run ARGS="+SINGLE_SEED=<n>"                  # reproduce one seed
make pl-run ARGS="+HEX=programs/hex/<test>.hex"      # change the bring-up smoke program
make pl-lint                                         # Verilator -Wall lint of the pipeline RTL
make run                                             # frozen single-cycle regression
```

Logs are written under `sim/build/pipeline_vcs/`. The end of `run.log` contains
the regression summary, the white-box assertion table with per-property
failure counts, the event counts behind each assertion, and the coverage lines
quoted above.

Correction (2026-09-30): through `make pl-run`, the `+SEED_OFFSET=1` in `ARGS`
has no effect. The Makefile passes a time-based `+SEED_OFFSET` first, and
`$value$plusargs` returns the first match, so the "release run" line above runs
time-seeded programs. The release numbers in the summary reproduce exactly
with `make pl-build` followed by
`./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500`
(checked on the v0.6.0 tree: `total_txns=5688`, `total_retired=29676`).

---

## 9. Next versions

Each version moves one boundary; any change inside the core is gated by this
release's regression.

| Version | Content | Core change |
|---|---|---|
| v0.6.0 | FPGA bring-up: synthesis, LUTRAM instruction memory, block-RAM data memory, top-level wrapper with clock and reset synchronization, pass/fail on an LED or UART TX | only if synthesis requires it |
| v0.7.0 | Request/response instruction fetch, so the instruction memory can live in block RAM; memory model with back-pressure | IF stage |
| later | Peripherals on a bus (UART, timer), interrupts with CSRs and trap handling, caches, external memory | — |

---

## Appendix A: Directed bring-up (2026-09-14)

Before the random flow was ported, six directed programs were run on the
pipeline and checked off-line against the single-cycle reference.

| Program | Static insns | Commits | Memory txns | Cycles | Trap PC |
|---|---|---|---|---|---|
| `alu_rtype_test` | 24 | 24 | 10 | 39 | `0x60` |
| `alu_itype_test` | 25 | 25 | 12 | 42 | `0x64` |
| `load_store_width_test` | 15 | 15 | 13 | 38 | `0x3c` |
| `branch_matrix_test` | 96 | 66 | 12 | 107 | `0x180` |
| `jump_u_type_test` | 15 | 10 | 3 | 24 | `0x3c` |
| `x0_test` | 15 | 15 | 8 | 30 | `0x3c` |

A cycle model — `cycles = commits + 4 (fill) + txns (second MEM cycle) +
2 × redirects + load-use stalls + 1` — reproduced all six cycle counts with zero
residual. The observed transaction streams matched the single-cycle expected
files line for line (58 transactions), and replaying the observed writes into a
byte-level memory model matched 51 of 51 final signature words.

Correction to the 2026-09-14 analysis: it listed `jump_u_type_test` as
exercising `WB_PC4` forwarding because a `JAL`'s link register is read by the
next instruction in static program order. In execution order that next
instruction is the jump target, which enters the pipeline after both younger
slots have been flushed and reads the link value through the WB→ID bypass.
`WB_PC4` forwarding is unreachable in this design (§5.2).
