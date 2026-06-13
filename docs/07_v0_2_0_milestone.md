# v0.2.0 Milestone: SystemVerilog R/I Direct Verification

## Summary

v0.2.0 is a learning-focused SystemVerilog and verification milestone.

Part of the single-cycle RTL and simulation flow was converted from Verilog to
SystemVerilog. The milestone also adds `tb/sv/ri_execute_tb.sv`, a directed,
self-checking testbench for the combined `control_unit`, `imm_gen`, and `alu`
path.

The testbench verifies these R/I operations:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, andi, ori, xori, slti, sltiu, slli, srli, srai
```

The existing v0.1 complete-core integration tests also continue to pass:

```text
add_test, sub_test, load_store_test, branch_test
```

## Main Changes

- Converted the ALU, control unit, immediate generator, top-level single-cycle
  core, register file, and shared definitions used by this branch toward
  SystemVerilog.
- Added `single_pkg.sv` for shared control types and RV32I constants.
- Added `ri_pkg.sv` for the R/I operation enum used by the direct test.
- Added a Verilator runner for the R/I direct test.
- Migrated the single-cycle simulation scripts and GitHub Actions flow from
  Icarus Verilog to Verilator.
- Kept the existing assembly-to-hex and signature-checking integration flow.

## What the Direct Test Checks

For each R/I operation, `ri_execute_tb.sv`:

1. Encodes a complete R-type or I-type instruction.
2. Drives representative source operands or immediate values.
3. Checks control-unit outputs and ALU-control selection.
4. Checks immediate extraction and sign extension for I-type instructions.
5. Computes an independent expected ALU result.
6. Compares the DUT result against that reference result.

All 19 current cases pass under Verilator.

## Learning Note and Technical Debt

The direct test is intentionally much larger than a maintainable production
testbench should be. It was written while practicing SystemVerilog features and
basic verification structure, so instruction encoding, expected-control logic,
reference execution, stimulus, and checking are all defined in one file.

This made the learning process explicit, but it also exposed a major design
problem: the testbench is roughly 350 lines, contains too many responsibilities,
and still focuses only on three modules (`alu`, `control_unit`, and `imm_gen`).
Adding every branch, load/store, jump, and corner case in the same style would
make it difficult to read, extend, and debug.

This structure is temporary. A later revision should separate:

- Instruction encoding helpers
- Reference-model functions
- Control and result checkers
- Reusable stimulus tasks
- Per-instruction-group test sequences

The current version is kept because it records the SystemVerilog learning
process, not because it represents the final verification architecture.

## Verilator Initialization Workaround

The earlier register-file and ideal-data-memory models cleared unpacked arrays
inside reset logic using a `for` loop and nonblocking assignments. This caused
compatibility problems in the current Verilator-based flow.

`regfile.sv` and `ideal_data_mem.v` were adjusted to avoid that reset-time array
clearing pattern, with simulation initialization moved outside the reset path
where applicable. The full current test suite passes after the change.

This is a simulator-flow workaround, not the final reset design. Portable
simulation behavior and synthesizable register-file reset semantics must be
revisited before the RTL is treated as production-ready.

## Verification Evidence

The following command passes:

```sh
make all
```

It runs:

- `add_test`
- `sub_test`
- `load_store_test`
- `branch_test`
- `ri_directed` with all 19 R/I cases

## Next Phase

1. Add the remaining branch variants with taken and not-taken cases.
2. Add load/store variants for different widths and signedness.
3. Add complete-core assembly tests for all newly covered R/I operations.
4. Refactor the large direct test into reusable verification helpers.
5. Restore simulator-independent initialization and reset semantics.
6. Add x0, illegal-instruction, reset, and alignment checks.
