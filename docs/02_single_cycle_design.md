# Single-Cycle Design

This document describes the current first-pass single-cycle datapath. The RTL structure is mostly connected, but this is still an uncompiled/unverified checkpoint until the ideal memory and testbench are written.

## Datapath Sketch

```text
pc_current
   |
   +--> instr_mem[pc] --> instr
   |                       |
   |                       +--> control_unit
   |                       +--> rs1/rs2/rd fields
   |                       +--> imm_gen
   |
   +--> pc + 4
   +--> pc + imm  // branch target

regfile rs1_data ----+
                     |
                     +--> ALU --> alu_result --> data memory / writeback
                     |
rs2_data / imm ------+

writeback:
  wb_data = wb_sel ? mem_rdata : alu_result
```

## Module Responsibilities

| Module | Responsibility |
|---|---|
| `pc` | Stores the current PC and updates to `pc_next` on each clock edge |
| `control_unit` | Decodes the instruction and generates register, memory, ALU, branch, immediate, and writeback control signals |
| `imm_gen` | Generates sign-extended immediates selected by `imm_sel` |
| `regfile` | Reads `rs1`/`rs2`, writes `rd`, and keeps x0 hardwired to zero |
| `alu` | Computes ADD/SUB results and produces `zero` for branch decisions |
| `core_single_cycle` | Connects the whole datapath, slices instruction fields, selects ALU/writeback inputs, drives memory ports, and chooses the next PC |

## Core Boundary

The single-cycle core does not contain instruction memory or data memory internally. It exposes a clean memory-facing boundary:

| Signal | Direction from core | Meaning |
|---|---|---|
| `imem_addr` | output | Instruction fetch address, currently equal to `pc_current` |
| `imem_rdata` | input | Instruction word returned by the external instruction memory |
| `dmem_read` | output | Load control signal |
| `dmem_write` | output | Store control signal |
| `dmem_addr` | output | Data memory address, currently driven by `alu_result` |
| `dmem_wdata` | output | Store data, currently driven by `rs2_data` |
| `dmem_rdata` | input | Load data returned by the external data memory |

This boundary is the reason the next task is an ideal memory or testbench wrapper: the core can generate addresses and memory control signals, but a simulation environment must still provide instruction words and load data.

## Main Equations

```verilog
instr         = imem_rdata;
imem_addr     = pc_current;
pc_plus_4     = pc_current + 32'd4;
branch_target = pc_current + imm;
branch_taken  = branch & alu_zero;
pc_next       = branch_taken ? branch_target : pc_plus_4;

alu_src_a     = rs1_data;
alu_src_b     = alu_src ? imm : rs2_data;
dmem_addr     = alu_result;
dmem_wdata    = rs2_data;
rd_data       = wb_sel ? dmem_rdata : alu_result;
```

## Timing Assumptions For This First Version

- PC and register writes are clocked on the rising edge.
- Instruction memory and data memory are assumed ideal for the first simulation model.
- Load data is expected to be available in the same cycle for the single-cycle model.
- Branch target selection happens inside the same cycle using the ALU `zero` result.

These assumptions are acceptable for a first single-cycle learning milestone. They will need to become more explicit before moving into a pipelined or realistic memory-interface version.
