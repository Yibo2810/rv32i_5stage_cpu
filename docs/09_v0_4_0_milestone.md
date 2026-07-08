# v0.4.0 Milestone: Constrained-Random Verification Freeze

## Summary

v0.4.0 freezes the verification environment for the single-cycle RV32I core.

The release moves the project from directed assembly regressions to a
self-contained constrained-random flow: a seed-reproducible program generator,
an instruction-set-simulator (ISS) reference model executing in lockstep with
the RTL, a transaction/register/retire scoreboard, a concurrent-assertion set
whose failures gate the regression verdict, and a functional coverage model
closed to 100% of its defined bins.

Validated release result (VCS, 200-seed regression):

```text
SUMMARY: 200 passed, 0 failed
ASSERTION FAILURES: 0
ALL RANDOM TESTS PASSED
RV_INSTR_COVERAGE  = 100.00%
RV_MEM_COVERAGE    = 100.00%
RV_BRANCH_COVERAGE = 100.00%
```

The directed assembly flow from v0.3.0 remains in place as the end-to-end
smoke baseline; the random flow is layered beside it, not on top of it.

## What the regression is

Each seed builds a random program of 20–40 static instructions from the
37-instruction supported subset, loads it into instruction memory, and runs
the ISS and the RTL against the same image:

```text
rv_program.build(seed)
  -> structured streams (randcase):
       straight-line ALU/memory instructions
       bounded loops (counted, guard + back-edge)
       forward conditional branches with controlled taken/not-taken
       JALR blocks with computed link targets
       store->load pairs with guaranteed non-zero data
  -> core_memory_model.imem
  -> rv_ref_model.run_iss()          (expected txns, regs, retire count)
  -> DUT executes until program end or budget
  -> core_scoreboard checks
```

Every seed is checked on three independent axes:

1. **Memory transaction stream** — count, order, direction, address, byte
   strobes, masked store data, and load data, one transaction at a time.
2. **Final architectural state** — registers `x1..x31` against the ISS.
3. **Retire semantics** — instruction count and final PC against the ISS.

A failing seed prints its reproduction command
(`make run ARGS="+SINGLE_SEED=<n>"`).

Two structural guards protect the regression from passing vacuously:

- an instruction/transaction density check fatals if the random programs stop
  producing observable memory activity;
- assertion failures accumulate in a counter that fails the whole run if
  non-zero, so protocol violations cannot hide inside a green summary.

## Stimulus design highlights

- **Bounded loops** emit a counted `ADDI/BEQ/.../ADDI -1/back-edge` shape with
  a generation-time self-check that the back edge lands exactly on the loop
  guard. The back edge is randomly a `JAL` or a `BNE x31, x0, -offset`, so
  backward taken branches with negative B-immediates are exercised
  continuously.
- **Forward branch streams** pick operand pairs per branch kind that
  distinguish signed from unsigned comparison semantics in both the taken and
  not-taken direction (all 12 kind × outcome combinations covered).
- **Store→load pairs** materialize a guaranteed non-zero (often negative)
  value via `LUI+ADDI`, store it, and immediately load it back — closing the
  anti-vacuity bin that proves load checking has seen real data
  (see case 10 in [10_bug_case_library.md](10_bug_case_library.md)).
- Memory-safety constraints keep random loads/stores inside the data window
  and naturally aligned; misalignment is a documented non-goal at this stage.

## Assertions

`core_assertions.sv` holds 15 concurrent properties bound to the memory
interface, covering: PC alignment, read/write exclusivity, no memory side
effects during reset, X-checks on all active control/address/data signals,
`dmem_read`/`dmem_write` implied only by load/store opcodes, load-address
alignment per width, store strobes consistent with width and address, and
`sys_ecall`/`sys_ebreak` known, mutually exclusive, and asserted only for
their exact instruction encodings.

Every property increments a shared `fail_count` on failure; the testbench
fatals at end of run if it is non-zero. This gate was added after a real
incident in which thousands of assertion failures coexisted with a green
summary (case 2 in the bug case library).

## Coverage results

### Functional coverage — 100% of defined bins

Execution-side sampling: the coverage module observes retired instructions at
the memory interface (not the generator), so loops count what actually ran
and dead code counts nothing. Branch outcome is derived from the next-cycle
PC using a one-stage `prev_pc/prev_instr` delay.

| Covergroup | Coverpoint | Bins | Result |
|---|---|---|---|
| `cg_instr` | `cp_opcode` | 9 | 100% |
| `cg_instr` | `cp_kind` (per instruction) | 37 | 100% |
| `cg_mem` | `cp_mem_kind` | 8 | 100% |
| `cg_mem` | `cp_store_wstrb` (byte lanes, half, word) | 7 | 100% |
| `cg_mem` | `cp_byte/half/word_load_offset` | 4+2+1 | 100% |
| `cg_mem` | `cp_load_data_nonzero` (anti-vacuity) | 2 | 100% |
| `cg_branch` | `cp_branch_kind` | 6 | 100% |
| `cg_branch` | `cp_branch_taken`, `cp_branch_dir`, direction × outcome cross | 2+2+4 | 100% |

Illegal encodings are `illegal_bins` (a hit is a test failure, not coverage);
misaligned accesses are `ignore_bins` with the exclusion documented in the
coverage source.

### Code coverage — DUT scope, with documented exclusions

Code coverage is collected on the core only (`-cm_hier` restricted to
`u_core`), so testbench error-reporting paths do not dilute the numbers.

| Metric | Result |
|---|---|
| Line | 101/116 (87.1%) |
| Branch | 93/106 (87.7%) |
| Condition | 62/76 (81.6%) |
| Toggle | 2373/2936 (80.8%) |

All remaining line/branch holes are in `control_unit` and consist of exactly
two categories, both intentional at this stage:

1. **SYSTEM decode** (`ecall`/`ebreak` behavior) — the generator does not emit
   SYSTEM instructions; the RTL outputs are instead pinned by assertions to
   never assert spuriously.
2. **Illegal-instruction default arms** — random programs contain only legal
   encodings; error-injection testing is future work.

Toggle residue is dominated by structurally unreachable bits under the
current memory map: upper PC bits (programs occupy a 1 KB window) and upper
data-address bits (loads/stores are constrained to the data window).

## Bugs found and fixed during this phase

The full write-ups live in [10_bug_case_library.md](10_bug_case_library.md).
Highlights:

- a JAL J-immediate bit-swap in `imm_gen` that had survived the v0.3.0
  directed regression (case 1);
- `sys_ecall`/`sys_ebreak` driven X for their entire lifetime, caught within
  one cycle by the first run of the new assertions — along with the discovery
  that assertion failures did not yet gate the regression verdict (case 2);
- an ISS write-back bug, a generator/oracle instruction-set mismatch, a
  retire-count off-by-one at reset release, and a false-fatal vacuity guard
  (cases 3–6);
- generator bugs that silently weakened stimulus semantics (cases 7–8);
- two coverage-exposed stimulus holes: loads that had only ever read zero,
  and the complete absence of backward branches (cases 10–11).

## Known limitations (explicitly not verified in v0.4.0)

- `ecall`/`ebreak` functional behavior. The decoder's trap flags are
  assertion-guarded against spurious assertion, but SYSTEM instructions are
  never executed. Deferred until the project has a trap/exception model.
- Illegal-instruction handling paths (no error injection yet).
- JALR targets with bit 0 set (the RTL clearing logic exists but stimulus
  only produces aligned targets) and `JAL` with `rd != x0` (the link datapath
  is exercised via JALR).
- `BGE`/`BGEU` with equal operands (the ALU's equal-operand comparison is
  verified via random R-type `SLT`/`SLTU`; the composed branch corner is
  not directly stimulated).
- Loads/stores with non-zero base registers or negative offsets (constrained
  away for memory safety; planned to open up in the pipeline phase).
- Load write-back values are checked through the final register state, not
  per-load; a commit/retire monitor is planned for the pipeline phase.

## Running the regression

```sh
make run                              # build + 200-seed random regression
make run ARGS="+SINGLE_SEED=<n>"      # reproduce one seed
make run ARGS="+NUM_SEEDS=<n>"        # change regression size
make cov                              # same regression with coverage collection
python3 scripts/parse_cov.py          # per-module and per-bin coverage report
```

Coverage data is written to `sim/build/core_vcs/simv.vdb`;
`scripts/parse_cov.py` reads the database directly and reports structural
coverage per module, functional coverage per coverpoint, and any zero-hit
bins as explicit holes.

## Next phase

With the single-cycle core and its verification environment frozen, the next
milestone is the five-stage pipeline: IF/ID/EX/MEM/WB partitioning,
forwarding, load-use stalls, and branch flushes — reusing this random
generator, ISS, and scoreboard with the monitor moved to a commit/retire
view.
