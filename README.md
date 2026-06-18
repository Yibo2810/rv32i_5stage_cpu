# RV32I 5-Stage CPU

A learning-oriented RV32I CPU project implemented in a mix of Verilog and
SystemVerilog.

The project starts from a minimal verified single-cycle subset, then grows toward
a classic five-stage pipeline. Later phases will add more RV32I instructions,
hazard handling, forwarding, branch flushes, stronger verification, and a more
realistic memory interface.

## Current Milestone

**feature/accomplish-single: expanded single-cycle RTL milestone**

This branch extends the single-cycle core beyond the earlier v0.2.0 R/I
direct-verification milestone. The RTL now includes a cleaner memory boundary
with byte write strobes, a load/store unit for byte/halfword/word accesses,
polarity-aware branch decisions for the full RV32I branch family, and redirect
support for `jal`/`jalr`. It also adds datapath support for `lui` and `auipc`
through explicit ALU source and writeback selection.

The verification architecture has been migrated from a shell-script + Verilog
testbench flow (`scripts/run_single_cycle.sh` + `tb/tb_single_cycle.v`) to a
**VCS-based SystemVerilog testbench** (`tb/sv/core/core_sv_tb.sv`). The new
testbench uses a modular architecture with a dedicated `core_mem_if` interface,
a clocked `core_memory_model` for combined instruction/data memory, and a
configuration-driven `core_verif_pkg` for test case management. This moves the
project into a professional-grade verification environment.

The committed regression flow remains intentionally small: assembly-level
single-cycle tests still cover `add`, `sub`, `addi`, `lw`, `sw`, and `beq`, while
`tb/sv/ri_execute_tb.sv` checks the R/I decode-to-execute path. The expanded
single-cycle behavior should be promoted into committed directed programs before
the project claims full integration coverage for every newly connected
instruction.

## Status

- [x] Project structure and documentation scaffold
- [x] Shared RV32I constants and control encodings
- [x] Single-cycle RTL for PC, register file, ALU, immediate generation, control, and top-level datapath
- [x] Ideal instruction/data memory models for simulation
- [x] ASM-to-HEX generation script for `$readmemh`
- [x] Self-checking single-cycle directed testbench
- [x] GitHub Actions flow for remote RTL simulation
- [x] Partial RTL conversion from Verilog to SystemVerilog
- [x] Directed R/I decode, immediate-generation, and ALU verification
- [x] Verilator-based local and CI simulation flow
- [x] Single-cycle RTL support for branch variants, jumps, upper immediates, and byte-lane memory access
- [x] Architectural side-effect gating for illegal instructions and misaligned memory accesses
- [x] VCS-based SystemVerilog testbench with modular interface and memory model
- [ ] Complete RV32I instruction set
- [ ] Stronger decoder legality checks for the expanded ISA
- [ ] Broader verification with more directed tests, assertions, and coverage
- [ ] Basic five-stage pipeline
- [ ] Forwarding and hazard handling

## Verified ISA Subset

v0.2.0 has two verification levels.

The current single-cycle RTL has datapath/control support for:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, andi, ori, xori, slti, sltiu, slli, srli, srai
lb, lh, lw, lbu, lhu, sb, sh, sw
beq, bne, blt, bge, bltu, bgeu
jal, jalr, lui, auipc
```

The SystemVerilog direct test verifies the decode/immediate/execute behavior of:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, andi, ori, xori, slti, sltiu, slli, srli, srai
```

These checks cover instruction encoding, control decode, immediate generation,
ALU-control selection, and ALU result comparison against a reference function.

The complete single-cycle integration regression still verifies:

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

### VCS-based SystemVerilog Testbench (primary)

The new modular testbench replaces the legacy shell-script flow with a
professional VCS environment:

```sh
make -f Makefile.vcs build   # compile
make -f Makefile.vcs run     # run
```

The architecture:

```text
core_sv_tb.sv
  ├── core_verif_pkg.sv     → test configs, check kinds, expected values
  ├── core_mem_if.sv        → unified clk/rst/memory interface with modports
  ├── core_memory_model.sv  → clocked imem/dmem with init, hex load, store
  └── core_single_cycle.sv  → DUT
```

Test cases are defined as `core_test_cfg_t` structs in the `initial` block. Each
config specifies a hex program, max cycles, check type, and expected signature.
The testbench drives reset, runs cycles with per-cycle signal display, and
self-checks dmem signatures against expected values.

### Legacy Shell-based Flow

Run both the single-cycle integration tests and the R/I SystemVerilog direct
test:

```sh
make all
```

Run only the R/I direct test:

```sh
make ri-sv
```

The R/I direct-test path is:

```text
ri_execute_tb.sv
  -> instruction encoders and reference functions
  -> control_unit + imm_gen + alu
  -> per-instruction self-checking PASS/FAIL
```

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
2. Installs Verilator and RISC-V binutils.
3. Generates hex files from assembly.
4. Runs the single-cycle directed test suite.
5. Uploads generated hex, disassembly dumps, logs, and waveforms as artifacts.

## File Guide

| Path | Role |
|---|---|
| `rtl/include/single_pkg.sv` | Shared SystemVerilog RV32I constants and control types |
| `rtl/single_cycle/` | Current mixed Verilog/SystemVerilog single-cycle CPU RTL |
| `rtl/pipeline/` | Future five-stage pipeline placeholders |
| `tb/tb_single_cycle.v` | Legacy self-checking integration testbench (shell flow) |
| `tb/sv/core/core_sv_tb.sv` | **VCS-based SystemVerilog testbench** — config-driven, self-checking |
| `tb/sv/core/core_mem_if.sv` | Clock/reset/memory interface with core/mem_model/monitor modports |
| `tb/sv/core/core_memory_model.sv` | Clocked unified instruction/data memory with init and byte-write store |
| `tb/sv/core/core_verif_pkg.sv` | Test configuration types, check kinds, and test ID enum |
| `tb/sv/core/core_monitor.sv` | Passive signal monitor (placeholder for assertions/coverage) |
| `tb/filelists/core_sv.f` | VCS compile filelist for the SV testbench |
| `Makefile.vcs` | VCS build/run targets for the SV testbench |
| `tb/sv/ri_execute_tb.sv` | R/I directed test for control, immediate generation, and ALU execution |
| `tb/sv/ri_pkg.sv` | R/I operation enum used by the direct test |
| `tb/models/ideal_instr_mem.v` | Ideal instruction memory loaded from `+HEX=<file>` |
| `tb/models/ideal_data_mem.v` | Ideal data memory used for load/store and final signatures |
| `programs/asm/` | Directed assembly test programs |
| `programs/hex/` | Generated machine-code words for `$readmemh` |
| `programs/expected/` | Human-readable expected test signatures |
| `scripts/asm_to_hex.sh` | Assembly-to-hex generation flow |
| `scripts/run_single_cycle.sh` | Single-cycle compile/run/check script |
| `scripts/run_ri_sv.sh` | Verilator runner for the R/I SystemVerilog direct test |
| `docs/` | Design, ISA, verification, and milestone notes |
| `sim/` | Generated simulation artifacts, ignored by Git |

## Known Limitations

- The 19 R/I operations are module-path directed tests, not yet complete
  assembly-level integration tests for the whole CPU.
- `ri_execute_tb.sv` is intentionally a learning exercise in SystemVerilog and
  verification. At roughly 350 lines, it mixes instruction encoding, expected
  control generation, reference execution, stimulus, and checking in one file.
  It is too verbose and tightly coupled for long-term maintenance and will be
  refactored after the learning goals are met.
- Committed branch integration coverage is still limited to the existing `beq`
  program even though the RTL now decodes all RV32I branch variants.
- Committed load/store integration coverage is still limited to word operations
  even though the RTL now supports byte and halfword lanes.
- The current memory model is ideal; it does not model wait states,
  instruction-address misalignment traps, or a bus protocol.
- `regfile.sv` and `ideal_data_mem.v` currently use a Verilator-oriented
  initialization workaround instead of reset-time array clearing with a
  `for` loop and nonblocking assignments. This passes the current tests, but
  portable reset and synthesis semantics must be revisited before treating the
  implementation as production RTL.
- Verification is directed and signature-based. Constrained-random testing,
  functional coverage, assertions, and UVM-style infrastructure are later work.
- The five-stage pipeline files are placeholders for the next major phase.

## Next Steps

1. Add committed integration programs for all branch variants with taken and not-taken cases.
2. Add committed integration programs for byte/halfword and signed/unsigned load/store variants.
3. Move the R/I direct-test helpers into smaller reusable packages/tasks.
4. Add complete-core assembly regressions for the R/I instructions currently
   covered only by `ri_execute_tb.sv`.
5. Restore simulator-independent reset semantics for the register file and
   ideal data memory.
6. Add x0, illegal-instruction, reset, and alignment-focused committed tests.
7. Start the five-stage pipeline only after the single-cycle baseline remains stable.
