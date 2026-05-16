# RV32I 5-Stage CPU

A learning-oriented RV32I CPU project implemented in Verilog.

The project starts from a minimal single-cycle RV32I core, then evolves into a classic five-stage pipeline. Hazard handling, forwarding, stalling, branch flushing, memory interfaces, and later system-level features will be added incrementally after the basic core is runnable and verified.

## Current Status

This repository is currently at an uncompiled single-cycle RTL checkpoint. The first-stage TODO placeholders have mostly been replaced with real single-cycle modules and top-level datapath wiring, but the design still needs an ideal memory model and a self-checking testbench before it should be described as functionally verified.

- [x] Project structure
- [x] Minimal RV32I ISA subset for the first single-cycle milestone
- [x] Common RV32I constants and control encodings
- [x] ALU for add/sub-style operations
- [x] Register file with x0 hardwired to zero
- [x] Immediate generator for the first supported formats
- [x] Control unit split into main decode and ALU decode logic
- [x] Single-cycle datapath wrapper with PC, decode, ALU, memory, writeback, and branch paths connected
- [ ] Ideal instruction/data memory model
- [ ] Self-checking single-cycle testbench
- [ ] Compile/lint cleanup after the first simulator run
- [ ] Basic five-stage pipeline
- [ ] Forwarding and hazard handling

## Current Local Snapshot

Compared with the initial GitHub commit, the local work has moved the single-cycle part of the repository from mostly TODO files to a concrete first-pass RTL design:

- Added shared definitions in `rtl/include/rv32i_defs.vh` for opcodes, funct fields, ALU controls, immediate selects, and writeback select.
- Implemented `pc`, `regfile`, `alu`, `imm_gen`, `control_unit`, and `core_single_cycle` under `rtl/single_cycle/`.
- Connected the single-cycle datapath around external instruction/data memory ports instead of hiding memory inside the core.
- Added/expanded early architecture documentation for the ISA subset, ALU, single-cycle datapath, and verification plan.
- Kept the pipeline, testbench, and simulation scripts as future work until the single-cycle core has an ideal memory wrapper and directed tests.

## Initial ISA Subset

The first single-cycle milestone only targets six RV32I instructions:

| Instruction | Type | Current RTL path | Purpose |
|---|---|---|---|
| `add` | R-type | Implemented, TB pending | Register-register addition |
| `sub` | R-type | Implemented, TB pending | Register-register subtraction |
| `addi` | I-type | Implemented, TB pending | Register-immediate addition |
| `lw` | I-type | Implemented, ideal memory/TB pending | Load word from data memory |
| `sw` | S-type | Implemented, ideal memory/TB pending | Store word to data memory |
| `beq` | B-type | Implemented, TB pending | Conditional branch if equal |

This subset is intentionally small. It is enough to exercise the core datapath: instruction fetch, decode, register read, ALU execution, memory access, writeback, and PC update.

## File Guide

| Path | Role | Current state |
|---|---|---|
| `rtl/include/rv32i_defs.vh` | Shared RV32I constants | Added local opcode, funct, ALU, immediate, and writeback definitions |
| `rtl/single_cycle/pc.v` | Program counter register | Holds current PC and updates to `pc_next` each cycle |
| `rtl/single_cycle/regfile.v` | 32-entry integer register file | Provides two read ports, one write port, reset clearing, and x0 protection |
| `rtl/single_cycle/alu.v` | Arithmetic/compare execution block | Supports ADD and SUB; `zero` is used by `beq` |
| `rtl/single_cycle/imm_gen.v` | Immediate decoder | Generates immediates selected by `imm_sel` |
| `rtl/single_cycle/control_unit.v` | Instruction decode and control | Generates memory, register, ALU, branch, immediate, and writeback control signals |
| `rtl/single_cycle/core_single_cycle.v` | Single-cycle top-level datapath | Connects PC, register file, immediate generation, control, ALU, memory ports, writeback, and branch next-PC logic |
| `rtl/pipeline/` | Future five-stage pipeline RTL | Still placeholder/TODO for later phases |
| `tb/tb_single_cycle.v` | Future single-cycle integration TB | Placeholder; next major task |
| `tb/common/test_utils.vh` | Shared testbench helper include | Placeholder; helpers/macros can be added with the TB |
| `programs/` | Assembly, hex, and expected outputs | Early directed program area for future simulation checks |
| `scripts/` | Simulation and utility scripts | Script entry points exist, but single-cycle simulation command is not implemented yet |
| `docs/` | Design and verification notes | Tracks the project plan, ISA subset, single-cycle design, ALU notes, pipeline notes, and verification plan |
| `sim/` | Generated simulation artifacts | Output directory for future waveforms/logs/build products |

## Next Steps

1. Add an ideal memory model or testbench wrapper that provides `imem_rdata` and `dmem_rdata` and captures `dmem_write`.
2. Build a self-checking `tb_single_cycle.v` that drives clock/reset, loads small hex programs, runs for a bounded number of cycles, and checks register or memory results.
3. Run directed tests for `add`, `sub`, `addi`, `lw`, `sw`, `beq`, x0 behavior, and reset behavior.
4. After the single-cycle core compiles and passes the directed tests, update the documentation from "uncompiled checkpoint" to "single-cycle verified baseline".

## Project Structure

```text
rtl/
  include/         Shared RV32I definitions
  single_cycle/    Single-cycle CPU implementation
  pipeline/        Future five-stage pipeline implementation

tb/                Testbenches
docs/              Architecture and verification notes
programs/          Assembly, hex, and expected test outputs
scripts/           Simulation and utility scripts
sim/               Simulation output directory
```
