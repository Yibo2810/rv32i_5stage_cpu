# RV32I 5-Stage CPU

A learning-oriented RV32I CPU project implemented in Verilog.

The project starts from a minimal verified single-cycle subset, then grows toward
a classic five-stage pipeline. Later phases will add more RV32I instructions,
hazard handling, forwarding, branch flushes, stronger verification, and a more
realistic memory interface.

## Current Milestone

**v0.1 single-cycle verified subset**

This milestone is a single-cycle CPU baseline for a small RV32I subset. The
subset has been run with directed assembly programs, generated machine-code hex
files, ideal instruction/data memories, and a self-checking integration
testbench. GitHub Actions also runs the same flow and uploads generated hex,
logs, and waveforms as artifacts.

This is not a complete RV32I implementation yet, and it is not the five-stage
pipeline version.

## Status

- [x] Project structure and documentation scaffold
- [x] Shared RV32I constants and control encodings
- [x] Single-cycle RTL for PC, register file, ALU, immediate generation, control, and top-level datapath
- [x] Ideal instruction/data memory models for simulation
- [x] ASM-to-HEX generation script for `$readmemh`
- [x] Self-checking single-cycle directed testbench
- [x] GitHub Actions flow for remote RTL simulation
- [ ] Complete RV32I instruction set
- [ ] Stronger decoder legality checks for the expanded ISA
- [ ] Broader verification with more directed tests, assertions, and coverage
- [ ] Basic five-stage pipeline
- [ ] Forwarding and hazard handling

## Verified ISA Subset

The v0.1 milestone verifies this intentionally small subset:

| Instruction | Type | Directed test coverage | Final signature |
|---|---|---|---|
| `add` | R-type | `add_test` | `dmem[0] = 12` |
| `sub` | R-type | `sub_test` | `dmem[0] = 5` |
| `addi` | I-type | Used by all current tests | Feeds arithmetic, branch, and memory tests |
| `lw` | I-type | `load_store_test` | Loaded value is stored back to `dmem[1]` |
| `sw` | S-type | `add_test`, `sub_test`, `load_store_test`, `branch_test` | Writes test signatures to data memory |
| `beq` | B-type | `branch_test` | Taken branch skips the wrong-path write |

The subset is enough to exercise instruction fetch, decode, register read,
immediate generation, ALU execution, load/store access, writeback, and branch
next-PC selection.

## Verification Flow

The current single-cycle verification flow is:

```text
programs/asm/*.S
  -> scripts/asm_to_hex.sh
  -> programs/hex/*.hex
  -> tb/models/ideal_instr_mem.v via $readmemh
  -> tb/tb_single_cycle.v runs the core
  -> tb/models/ideal_data_mem.v captures store signatures
  -> PASS/FAIL from expected dmem values
```

Run all single-cycle directed tests:

```sh
make single
```

Run one directed test:

```sh
./scripts/run_single_cycle.sh add_test
```

Regenerate machine-code hex only:

```sh
./scripts/asm_to_hex.sh
```

If hex files have already been generated:

```sh
SKIP_ASM=1 ./scripts/run_single_cycle.sh
```

The runner currently checks:

```text
add_test        -> dmem[0] = 0000000c
sub_test        -> dmem[0] = 00000005
load_store_test -> dmem[1] = 0000002a
branch_test     -> dmem[0] = 00000001
```

## GitHub Actions

Remote verification is defined in `.github/workflows/rtl.yml`.

The workflow:

1. Checks out the repository.
2. Installs Icarus Verilog and RISC-V binutils.
3. Generates hex files from assembly.
4. Runs the single-cycle directed test suite.
5. Uploads generated hex, disassembly dumps, logs, waveforms, and the compiled simulation image as artifacts.

## File Guide

| Path | Role |
|---|---|
| `rtl/include/defs.vh` | Shared RV32I constants |
| `rtl/single_cycle/` | Current v0.1 single-cycle CPU RTL |
| `rtl/pipeline/` | Future five-stage pipeline placeholders |
| `tb/tb_single_cycle.v` | Self-checking integration testbench |
| `tb/models/ideal_instr_mem.v` | Ideal instruction memory loaded from `+HEX=<file>` |
| `tb/models/ideal_data_mem.v` | Ideal data memory used for load/store and final signatures |
| `programs/asm/` | Directed assembly test programs |
| `programs/hex/` | Generated machine-code words for `$readmemh` |
| `programs/expected/` | Human-readable expected test signatures |
| `scripts/asm_to_hex.sh` | Assembly-to-hex generation flow |
| `scripts/run_single_cycle.sh` | Single-cycle compile/run/check script |
| `docs/` | Design, ISA, verification, and milestone notes |
| `sim/` | Generated simulation artifacts, ignored by Git |

## Known Limitations

- Only `add`, `sub`, `addi`, `lw`, `sw`, and `beq` are in the verified subset.
- Other RV32I instructions are intentionally deferred, including logical ops,
  shifts, comparisons, other branches, jumps, `lui`, `auipc`, byte/halfword
  loads and stores, CSR instructions, and traps.
- The current memory model is ideal and word-oriented; it does not model byte
  enables, wait states, misalignment exceptions, or a bus protocol.
- Verification is directed and signature-based. Constrained-random testing,
  functional coverage, assertions, and UVM-style infrastructure are later work.
- The five-stage pipeline files are placeholders for the next major phase.

## Next Steps

1. Expand the single-cycle ISA subset in small groups.
2. Add directed tests for each new instruction group before moving on.
3. Tighten decoder legality checks as the ISA grows.
4. Add x0/reset/alignment-focused tests.
5. Start the five-stage pipeline only after the single-cycle baseline remains stable.
