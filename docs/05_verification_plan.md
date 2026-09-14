# Verification Plan

## Current Verification Status

The project has two verification states side by side:

| Phase | Flow | Status |
|---|---|---|
| Single-cycle core (v0.3.0 directed → v0.4.0 constrained-random) | `tb/sv/core/` under VCS | Frozen and verified as of v0.4.0; **not re-run** since `control_unit`, `load_store_unit` and `core_single_cycle` were touched while landing the pipeline |
| Five-stage pipeline (v0.5.0, in progress) | `tb/sv/pipeline/` under VCS | Directed bring-up only: six directed programs, "halted on `ebreak`" verdict, no oracle inside the testbench, no random flow |

The pipeline state is documented in detail in
[11_v0_5_0_pipeline_bringup.md](11_v0_5_0_pipeline_bringup.md); its design is in
[03_pipeline_design.md](03_pipeline_design.md) and
[04_hazard_forwarding.md](04_hazard_forwarding.md).

The frozen single-cycle flow is a VCS-based SystemVerilog harness:

```text
programs/asm/*.S
  -> scripts/asm_to_hex.sh
  -> programs/hex/*.hex
  -> tools/rv32i_ref.py
  -> programs/expected/*.expected
  -> tb/sv/core/core_sv_tb.sv
  -> core_memory_model + core_monitor + core_scoreboard
```

The regression is self-checking. It compares generated expected memory
transactions against observed transactions and also checks final data-memory
signature words.

Validated release command:

```sh
./scripts/asm_to_hex.sh
./tools/rv32i_ref.py --all
make run
```

Release result:

```text
ALL CORE SV TESTS PASSED
```

## Testbench Architecture

| File | Responsibility |
|---|---|
| `core_verif_pkg.sv` | Shared verification data structures |
| `core_test_db.sv` | Test metadata database |
| `core_mem_if.sv` | Instruction/data memory interface |
| `core_memory_model.sv` | Unified instruction/data memory model |
| `core_monitor.sv` | Passive transaction monitor |
| `core_scoreboard.sv` | Expected-vs-observed comparison |
| `core_assertions.sv` | Assertion scaffold |
| `core_sv_tb.sv` | Top-level reset, load, run, and check orchestration |
| `tools/rv32i_ref.py` | Repository-specific reference expected generator |

The intended boundary is:

- The monitor observes actual behavior.
- The scoreboard decides pass/fail.
- The memory model responds to DUT requests and exposes final signatures.
- The test database describes which tests exist.
- The reference model predicts expected behavior from generated hex.

## Current Directed Tests

| Test | Purpose |
|---|---|
| `x0_test` | Verify `x0` write protection and read-zero behavior |
| `alu_itype_test` | Verify complete I-type ALU behavior through the core |
| `alu_rtype_test` | Verify complete R-type ALU behavior through the core |
| `load_store_width_test` | Verify byte/halfword/word stores and signed/unsigned loads |
| `branch_matrix_test` | Verify all RV32I branch conditions, taken and not-taken |
| `jump_u_type_test` | Verify `lui`, `auipc`, `jal`, and `jalr` |
| `hazard_test` | **stub** — `programs/asm/hazard_test.S` is a TODO comment and `programs/hex/hazard_test.hex` is empty |

The historical smoke tests and the old direct R/I module-path test are no longer
the primary release gate. The release gate is the core-level VCS regression in
`tb/sv/core/`.

## Checker Strategy

### Transaction Check

The monitor records memory events. The scoreboard compares them against
generated `TXN` records:

```text
TXN W <addr> <data> <wstrb>
TXN R <addr> <data> <wstrb>
```

This is useful for memory width, byte mask, load/store, and ordering behavior.

### Signature Check

At the end of a test, the testbench reads data memory through `peek_word()` and
compares final architectural signatures against `SIG` records:

```text
SIG <addr> <data>
```

This is useful for instruction-level architectural results and keeps directed
programs simple.

## Assertions

The single-cycle assertion layer (`tb/sv/core/core_assertions.sv`, 15
concurrent properties) is intentionally lightweight. It catches structural
mistakes early without replacing the scoreboard.

Planned assertion areas (all of these shipped in the v0.4.0 single-cycle
assertion set; the pipeline needs its own set, listed in the pipeline section
at the end of this document):

- PC alignment during instruction fetch
- legal memory byte-enable patterns
- no unknown values on active memory transactions
- reset release behavior
- `x0` invariants where observable
- mutually consistent memory read/write behavior
- max-cycle watchdog behavior

## Functional Coverage

The next verification step is coverage, not immediately full random. First
coverage targets:

| Coverage point | Examples |
|---|---|
| opcode family | R/I/load/store/branch/jump/U-type |
| ALU operation | arithmetic, logical, compare, shift |
| load width | byte, halfword, word, signed, unsigned |
| store mask | `0001`, `0010`, `0100`, `1000`, `0011`, `1100`, `1111` |
| branch condition | BEQ/BNE/BLT/BGE/BLTU/BGEU |
| branch direction | taken, not-taken |
| redirect type | PC+4, branch target, JAL, JALR |
| register zero | read-zero, ignored write |

Coverage answers "what did we exercise?" It does not replace pass/fail checks.

## Constrained-Random Roadmap

Constrained-random should build on the current directed flow:

```text
seed
  -> generated assembly
  -> hex
  -> rv32i_ref.py expected file
  -> SV testbench
  -> scoreboard
```

Generator constraints should include:

- supported instruction subset
- initialized source registers
- bounded data-memory range
- aligned accesses unless a negative test explicitly targets misalignment
- bounded branch targets
- no uncontrolled infinite loops
- deterministic seed logging

Random tests should be added only when they have an oracle and can be
reproduced from a seed.

## Five-Stage Pipeline Verification (v0.5.0, in progress)

The pipeline phase started from that baseline: the generator, the ISS, the
scoreboard concepts and the expected-file format are all microarchitecture
independent, so the transition is mostly a change of *view* for the monitor
(from "what is on the bus" to "what retired").

The key rule is unchanged:

**the scoreboard checks architectural behavior; the monitor adapts to the
microarchitecture.**

### Implemented today

| File | Responsibility |
|---|---|
| `tb/sv/pipeline/pipeline_tb.sv` | Reset, load one `.hex`, run until `halted`, dump, verdict |
| `tb/sv/pipeline/pipeline_probe_if.sv` | `pipeline_probe_if`: core/memory wires with `pl_core`, `bram`, `pipeline_monitor` modports and a clocking block |
| `tb/sv/pipeline/pipeline_memory.sv` | 256-word imem pre-filled with `ebreak` + `$readmemh` overlay; dmem = `dmem_bram #(.DEPTH(256))` |
| `tb/sv/pipeline/pipeline_monitor.sv` | Passive capture of commits (from `wb_retire`), memory transactions (paired request/response), and trap count/cause/PC |
| `tb/filelists/pipeline.f` | Pipeline compile order (scoreboard/assertions/random entries currently commented out) |
| `tb/filelists/pipeline_rtl.f` | RTL compile order, shared by `make pl-lint` and `make pl-build` |

The monitor watches a genuine retire view: `retire = wb_retire`,
`retire_pc = memwb_q.pc`, `retire_next_pc = memwb_q.next_pc`, plus the register
write port (`wb_w_en`/`wb_rd_addr`/`wb_rd_data`). That is the abstraction the
single-cycle phase lacked.

### Verdict today

`BRINGUP DONE` iff no timeout and exactly one trap with cause
`EXC_BREAKPOINT`. Memory transactions and commits are dumped for inspection but
**not compared against expected values inside the testbench**.

Six directed programs were run on 2026-09-14 and all six halted on `ebreak`
with plausible commit/transaction counts. As an off-line check, each program's
observed transaction stream was compared against
`programs/expected/<test>.expected` and matched line for line (58 transactions
total), with 51/51 final signature words matching when the observed writes are
replayed into a byte-level data-memory model. Details and the per-test table:
[11_v0_5_0_pipeline_bringup.md](11_v0_5_0_pipeline_bringup.md).

### Not yet in place

- **No oracle in the testbench.** The expected-file comparison above is an
  ad-hoc script run, not a checker.
- **Scoreboard and assertions not adapted.** `pipeline_scoreboard.sv` and
  `pipeline_assertions.sv` are still single-cycle copies (`core_verif_pkg` /
  `core_mem_if` based) and are excluded from the pipeline filelist.
- **No random flow.** `tb/sv/pipeline/random/pl_*.sv` (package `rv_random_pkg`)
  exist but are commented out of `tb/filelists/pipeline.f`; the testbench has no
  random mode.
- **No coverage.** No `-cm` targets and no pipeline covergroups.
- **Missing directed tests.** `hazard_test.S` is a stub; there is no
  misaligned load/store, illegal-instruction, `ecall`, request-back-pressure, or
  deliberate hazard-chain program in `programs/asm/`.
- **Single-cycle regression not re-run** since the shared leaf modules changed.

### Planned pipeline checks

```text
commit/retire monitor        already present
expected TXN/SIG per test    move the off-line comparison into the scoreboard
                            (memory transactions + final dmem signatures)
ISS lockstep                 compare retire count, final PC and architectural state
                            against rv_ref_model once the random flow is enabled
pipeline assertions          single retire per instruction; no flush during a
                            memory freeze; req_sent -> !req_valid;
                            !(wb_exc_pending && req_sent); halted -> no request
                            and no writeback; trap_cause valid only with trap_valid
hazard-specific directed     load-use, double forwarding, EX/MEM load guard,
  tests                      WB_PC4 forwarding, trap during a freeze
back-pressure stimulus       randomise dmem_req_ready and verify request stability
coverage                     hazards, redirects, stalls, trap causes, widths
```

Order of work: get an oracle inside the testbench first (directed), then hazard
directed tests, then enable the random flow, then coverage closure.
