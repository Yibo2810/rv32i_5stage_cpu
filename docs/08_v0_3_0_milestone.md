# v0.3.0 Milestone: Verified Single-Cycle Core

## Summary

v0.3.0 completes the single-cycle milestone for the supported RV32I base integer
datapath.

The release moves the project from small smoke tests and module-path direct
tests into a reusable core-level SystemVerilog verification architecture. The
primary simulation target is now the VCS testbench under `tb/sv/core/`.

Validated release result:

```text
ALL CORE SV TESTS PASSED
```

Validated on `yibo-server` with:

```text
Synopsys VCS
```

## Main Changes

- Expanded the single-cycle core verification target to cover the supported
  RV32I base integer datapath.
- Added directed assembly tests for R-type ALU, I-type ALU, load/store width,
  branch matrix, jump/U-type behavior, and `x0`.
- Replaced hand-written expected values in the SV database with generated
  expected files under `programs/expected/`.
- Added `tools/rv32i_ref.py`, a small repository-specific RV32I reference model
  that generates `TXN` and `SIG` expected records.
- Slimmed the test database so it stores test metadata instead of hard-coded
  expected transactions.
- Added a transaction-oriented scoreboard and final signature checks.
- Preserved the monitor/scoreboard boundary needed for the future five-stage
  pipeline.

## Verified Instruction Groups

```text
R-type ALU:
  add, sub, and, or, xor, slt, sltu, sll, srl, sra

I-type ALU:
  addi, slti, sltiu, xori, ori, andi, slli, srli, srai

Load/store:
  lb, lh, lw, lbu, lhu, sb, sh, sw

Branch:
  beq, bne, blt, bge, bltu, bgeu

Jump and upper immediate:
  jal, jalr, lui, auipc

Architectural invariant:
  x0 writes are ignored and x0 reads as zero
```

## Release Regression

Release command sequence:

```sh
./scripts/asm_to_hex.sh
./tools/rv32i_ref.py --all
make run
```

The regression runs:

| Test | Result |
|---|---|
| `x0_test` | PASS |
| `alu_itype_test` | PASS |
| `alu_rtype_test` | PASS |
| `load_store_width_test` | PASS |
| `branch_matrix_test` | PASS |
| `jump_u_type_test` | PASS |

The scoreboard reports both transaction and signature checks. Example final
marker:

```text
ALL CORE SV TESTS PASSED
```

## Verification Architecture

```text
programs/asm/*.S
  -> scripts/asm_to_hex.sh
  -> programs/hex/*.hex
  -> tools/rv32i_ref.py
  -> programs/expected/*.expected
  -> core_sv_tb.sv
  -> core_memory_model + core_monitor
  -> core_scoreboard
```

Expected files use:

```text
TXN W <addr_hex> <data_hex> <wstrb_bin>
TXN R <addr_hex> <data_hex> <wstrb_bin>
SIG <addr_hex> <data_hex>
```

This keeps expected results out of the SystemVerilog source while still making
the oracle readable and diffable.

## Scope Boundary

This release claims:

- verified single-cycle execution for the listed RV32I base integer operations
- directed core-level tests under VCS
- transaction and signature scoreboard checks
- a reusable verification architecture for the next phase

This release does not claim:

- constrained-random verification
- functional coverage closure
- UVM
- full exception/trap behavior
- CSR or privileged ISA behavior
- verified five-stage pipeline behavior

## Known Notes

- `tools/rv32i_ref.py` is intentionally a small local oracle for the repository's
  bare-metal snippets, not a complete ISS.
- The current monitor focuses on memory transactions. A commit/retire monitor is
  the next major verification abstraction before serious pipeline checking.
- VCS may print non-fatal package wildcard import notes during compile.

## Next Phase

1. Add assertions for PC alignment, memory byte-enable legality, active bus
   no-X checks, and reset invariants.
2. Add lightweight functional coverage for opcode groups, branch directions,
   memory widths, byte masks, redirects, and `x0`.
3. Add constrained-random program generation using deterministic seeds.
4. Reuse the existing expected-file and scoreboard flow for random tests.
5. Start the five-stage pipeline: IF, ID, EX, MEM, WB.
6. Add forwarding, load-use stall, branch flush, valid/kill bits, and pipeline
   commit/retire monitoring.
