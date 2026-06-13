# Verification Plan

## Current Verification Status

The project has reached **v0.2.0 SystemVerilog R/I direct verification**.

There are now two directed, self-checking verification levels.

In the original integration flow, assembly programs under `programs/asm/` are
assembled into `programs/hex/`, loaded into the ideal instruction memory with
`$readmemh`, executed by `tb/tb_single_cycle.v`, and checked through final
data-memory signatures. It verifies `add`, `sub`, `addi`, `lw`, `sw`, and `beq`
through the complete single-cycle core.

The v0.2.0 SystemVerilog flow uses `tb/sv/ri_execute_tb.sv` to directly connect
and check `control_unit`, `imm_gen`, and `alu`. It verifies these 19 R/I
operations:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, andi, ori, xori, slti, sltiu, slli, srli, srai
```

The R/I test is a real module-path verification milestone, but it is not
complete-core coverage for all 19 operations. It is also not random
verification, functional coverage, UVM, or full RV32I verification.

## R/I Direct Test Design Note

`ri_execute_tb.sv` was intentionally written as a SystemVerilog and verification
learning exercise. It currently contains instruction encoders, expected-control
logic, a reference ALU model, stimulus, and checks in one file. This made each
step visible while learning, but the result is roughly 350 lines and is too
verbose and tightly coupled for long-term maintenance.

The testbench should later be split into reusable instruction builders,
reference-model helpers, checkers, and instruction-group test tasks. The current
form is retained temporarily because its purpose is learning, not establishing
the final verification architecture.

## Current Directed Tests

| Test | Purpose | Expected check |
|---|---|---|
| `add_test` | Check `addi`, register-register `add`, writeback, and store signature | `dmem[0] = 12` |
| `sub_test` | Check `addi`, register-register `sub`, writeback, and store signature | `dmem[0] = 5` |
| `load_store_test` | Check effective address generation, `sw`, `lw`, and load writeback | `dmem[1] = 42` |
| `branch_test` | Check taken `beq`, B-type immediate, and next-PC selection | `dmem[0] = 1` |
| `ri_directed` | Check R/I instruction encoding, control decode, immediate generation, ALU-control selection, and ALU results | All 19 instruction cases report `PASS` |

## Local Run Flow

Run the full current regression:

```sh
make all
```

Run only the single-cycle integration tests:

```sh
make single
```

Equivalent direct command:

```sh
./scripts/run_single_cycle.sh
```

Run one test:

```sh
./scripts/run_single_cycle.sh add_test
```

Run the R/I SystemVerilog direct test:

```sh
make ri-sv
```

Regenerate hex files only:

```sh
./scripts/asm_to_hex.sh
```

The run scripts compile the RTL and testbenches with Verilator and invoke the
generated simulation executables with plusargs such as:

```text
+HEX=programs/hex/add_test.hex
+EXPECT_ADDR=0
+EXPECT_VALUE=0000000c
```

In actual command-line form these are passed as `+HEX=...`, `+EXPECT_ADDR=...`,
and `+EXPECT_VALUE=...`.

## GitHub Actions Flow

Remote verification is defined in `.github/workflows/rtl.yml`.

The workflow installs the RTL/simulation dependencies, runs `asm_to_hex.sh`,
runs the single-cycle simulation suite, and uploads artifacts:

- Generated machine-code hex files
- Preprocessed assembly files
- Disassembly dumps
- Simulation logs
- VCD waveforms

## Verilator Compatibility Note

The earlier register-file and ideal-data-memory models cleared unpacked arrays
during reset with a `for` loop and nonblocking assignments. That form caused
problems in the current Verilator-based learning flow. `regfile.sv` and
`ideal_data_mem.v` were therefore adjusted to remove reset-time array clearing;
the simulation memory is initialized in an `initial` block where applicable.

The current regression passes with this workaround. It should not be treated as
a general claim that Verilator cannot support reset loops, nor as the final
synthesizable reset strategy. Simulator-independent initialization and reset
semantics remain follow-up work.

## Near-Term Verification Additions

The next useful tests are still directed tests:

- All branch variants, including taken and not-taken behavior.
- Load/store variants for byte, halfword, word, signed, and unsigned behavior.
- Complete-core programs for all R/I operations currently covered only by the
  module-path direct test.
- `x0_test`: writes to x0 must not change its read value.
- Reset tests after portable register-file reset semantics are restored.
- Illegal-instruction and alignment/bounds checks.
- Refactoring of `ri_execute_tb.sv` into reusable verification components.

## Later Verification Work

After the single-cycle ISA subset grows, add:

- More instruction-group directed tests
- Lightweight assertions for x0, PC alignment, and memory access assumptions
- Functional coverage for opcode groups and branch taken/not-taken behavior
- A simple reference model or ISS comparison for larger programs
- Constrained-random stimulus only after the supported ISA subset is well-defined

Pipeline verification should start only after the single-cycle baseline remains
stable. Later pipeline test areas include:

- IF/ID/EX/MEM/WB pipeline register behavior
- Forwarding paths
- Load-use stalls
- Branch flush behavior
- Multi-instruction regression programs
