# Verification Plan

## Current Verification Status

The project has reached **v0.1 single-cycle verified subset**.

The current verification flow is directed and self-checking. Assembly programs
under `programs/asm/` are assembled into `programs/hex/`, loaded into the ideal
instruction memory with `$readmemh`, executed by `tb/tb_single_cycle.v`, and
checked through final data-memory signatures.

This is a real integration test milestone for the current subset, but it is not
yet random verification, functional coverage, UVM, or full RV32I verification.

## Current Directed Tests

| Test | Purpose | Expected check |
|---|---|---|
| `add_test` | Check `addi`, register-register `add`, writeback, and store signature | `dmem[0] = 12` |
| `sub_test` | Check `addi`, register-register `sub`, writeback, and store signature | `dmem[0] = 5` |
| `load_store_test` | Check effective address generation, `sw`, `lw`, and load writeback | `dmem[1] = 42` |
| `branch_test` | Check taken `beq`, B-type immediate, and next-PC selection | `dmem[0] = 1` |

## Local Run Flow

Run all current single-cycle tests:

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

Regenerate hex files only:

```sh
./scripts/asm_to_hex.sh
```

The run script compiles the single-cycle RTL and testbench with Icarus Verilog,
then invokes `vvp` once per directed test with plusargs such as:

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
- Compiled Icarus simulation image

## Near-Term Verification Additions

The next useful tests are still directed tests:

- `x0_test`: writes to x0 must not change its read value.
- `reset_test`: PC and registers should reset to zero.
- Branch not-taken test: `beq` should fall through when operands differ.
- Negative immediate tests: sign extension for I/S/B immediates.
- Alignment/bounds checks for the ideal memory model.

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
