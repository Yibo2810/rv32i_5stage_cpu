# Verification Plan

## Current Verification Status

The project has three verification states side by side:

| Phase | Flow | Status |
|---|---|---|
| Single-cycle core (v0.3.0 directed → v0.4.0 constrained-random) | `tb/sv/core/` under VCS | Frozen and verified as of v0.4.0; re-run on the v0.5.0 tree after the shared leaf modules were edited: 200 seeds, zero assertion failures, 100% of defined bins |
| Five-stage pipeline (v0.5.0) | `tb/sv/pipeline/` under VCS | Frozen and verified in simulation: ISS lockstep on the commit stream, 500 seeds, interface and white-box assertions gating the verdict, coverage closed except an enumerated waiver list; re-run on the v0.6.0 tree with offset 1 (2026-09-30): identical totals |
| FPGA system wrapper (v0.6.0) | `rtl/fpga/tb/fpga_sys_tb.sv` under VCS, then the Arty A7-100T | Self-checking `hazard_test` passes in simulation and on the board (board smoke test); passing case only, fail path not yet exercised |

The pipeline state is documented in detail in
[11_v0_5_0_milestone.md](11_v0_5_0_milestone.md); its design is in
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
| `hazard_test` | Pipeline hazards (load-use, EX/MEM and MEM/WB forwarding, redirects with squashed loads/stores/branches, a redirect deferred by a memory stall), followed by a self-checking tail that compares the 15 signature words and writes a verdict to `tohost` (`0x3FC`); also the v0.6.0 board program |

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

## Five-Stage Pipeline Verification (v0.5.0)

The pipeline phase kept the single-cycle design and changed the view: the
generator, the ISS and the scoreboard concepts are microarchitecture
independent, so the port was mostly a move from "what is on the bus" to "what
retired".

The key rule is unchanged:

**the scoreboard checks architectural behavior; the monitor adapts to the
microarchitecture.**

### Environment

| File | Responsibility |
|---|---|
| `tb/sv/pipeline/pipeline_tb.sv` | Bring-up smoke program, then the seed loop: build, clear data memory, ISS, run, four checks, per-seed assertion gating, summary |
| `tb/sv/pipeline/pipeline_probe_if.sv` | Core/memory wires plus MEM-stage identity (`mem_pc`, `mem_instr`) and the retire port, with a clocking block |
| `tb/sv/pipeline/pipeline_memory.sv` | 256-word imem pre-filled with `ebreak`; `dmem_bram #(.DEPTH(256))`, cleared per seed |
| `tb/sv/pipeline/pipeline_monitor.sv` | Retired instructions (from `wb_retire`, excluding the trapping one), memory transactions (request paired with response), trap events |
| `tb/sv/pipeline/pipeline_scoreboard.sv` | Commit stream (per instruction; `rd_addr`/`rd_data` compared only when `rd_we = 1`), transaction stream, retire count/final PC, register file |
| `tb/sv/pipeline/pipeline_assertions.sv` | 11 interface properties on the memory ports and the MEM-stage instruction |
| `tb/sv/pipeline/pipeline_sva_bind.sv` | 13 white-box properties bound into `core_5stage`; forwarding / load-use / redirect covergroups |
| `tb/sv/pipeline/random/` | `pl_instr`, `pl_program` (hazard bias and pipeline templates), `pl_ref_model` (ISS), `pl_coverage` (ISA coverage at retirement) |

### Rules that came out of the port

- **Both sides of a property must belong to the same pipeline stage.** A
  memory request is judged against the MEM-stage instruction, never against the
  instruction being fetched.
- **Compare a field only when it is defined.** `rd_data` is meaningless when
  `rd_we = 0`; the `rd` field of a store or branch is never encoded; the
  `rs1`/`rs2` fields of instructions that do not read registers are immediate
  bits. Each of these produced a false failure or a silently wrong statistic.
- **Combinational control is checked in the same cycle** (`|->`), and events
  that a higher-priority hazard can freeze are only checked in the cycle they
  act.
- **Put a property's conclusion on a single-cause signal.** `pc_stall` has three
  causes, so "the stall ended" is checked on the hazard signal itself.
- **Every assertion has a cover on its antecedent**, and every checker must be
  able to fail the regression: white-box failures are compared per seed.
- **Structural coverage holes are fixed in the generator's templates**, not by
  running more seeds.
- **Checkers are validated by injecting bugs.** Four mutants of the hazard logic
  each fail the regression.

### Result and what remains

The release result, coverage numbers, waiver list and mutation table are in
[11_v0_5_0_milestone.md](11_v0_5_0_milestone.md). Still open after v0.5.0:

```text
back-pressure stimulus       randomise dmem_req_ready and response latency;
                             add request-stability assertions
trap paths                   illegal instruction, ecall, misaligned access,
                             trap with a younger store in MEM
waived coverage              sub-word loads into branches/JALR/addresses,
                             load into branch rs2, deferred JAL/JALR redirects,
                             control-flow instruction in a redirect shadow
external reference           riscv-arch-test signatures, Spike or Sail
```

`programs/asm/hazard_test.S`, a stub at v0.5.0, was written for v0.6.0 (see the
directed-test table above and [12_v0_6_0_milestone.md](12_v0_6_0_milestone.md)).
It runs in `fpga_sys_tb` and on the board; the `pipeline_tb` `+HEX=` smoke run
only dumps it and does not compare it against its expected file.
