# Verification Plan

## Current Verification Status

The project has reached **v0.3.0 verified single-cycle core**.

The active verification flow is a VCS-based SystemVerilog harness:

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

The first assertion layer is intentionally lightweight. It should catch
structural mistakes early without replacing the scoreboard.

Planned assertion areas:

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

## Five-Stage Pipeline Verification Plan

The current architecture is designed so that much of it survives the transition
to a pipeline.

Reusable from single-cycle:

- assembly programs
- generated hex files
- generated expected files
- memory model, with minor interface adaptation if needed
- scoreboard concepts
- test database structure

Expected pipeline-specific additions:

- commit/retire monitor
- IF/ID, ID/EX, EX/MEM, MEM/WB pipeline register checks
- forwarding tests
- load-use stall tests
- branch flush tests
- valid/kill bit assertions
- pipeline coverage for hazards and redirects

The key rule is:

**scoreboard checks architectural behavior; monitor adapts to the
microarchitecture.**

That keeps the v0.3.0 verification work useful instead of becoming a disposable
single-cycle-only testbench.
