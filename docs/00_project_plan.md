# Project Plan

## Goals

- Build a minimal RV32I single-cycle CPU.
- Extend the design to a 5-stage pipeline.
- Verify correctness with focused assembly programs and testbenches.

## Current Checkpoint

The first implementation phase has moved the single-cycle design from TODO placeholders into a first-pass RTL structure. The local tree now includes implemented single-cycle modules for PC, register file, ALU, immediate generation, control, and the top-level datapath wrapper.

This checkpoint is intentionally marked as uncompiled/unverified. The datapath is substantially connected, but the project still needs an ideal memory model and a self-checking testbench before the single-cycle CPU can be claimed as verified.

## Milestones

| Phase | Milestone | Status |
|---|---|---|
| 0 | Repository structure and learning-oriented documentation scaffold | Done |
| 1 | Minimal ISA subset and single-cycle RTL modules | Mostly done, compile/TB pending |
| 2 | Ideal instruction/data memory and self-checking single-cycle testbench | Next |
| 3 | Directed single-cycle programs and result checking | Next |
| 4 | Five-stage pipeline partitioning | Planned |
| 5 | Hazard detection, forwarding, stall, and flush logic | Planned |
| 6 | Regression scripts and broader verification | Planned |

## Immediate Next Work

1. Define the first ideal memory boundary around `imem_addr`, `imem_rdata`, `dmem_addr`, `dmem_wdata`, `dmem_rdata`, `dmem_read`, and `dmem_write`.
2. Write `tb/tb_single_cycle.v` as a self-checking integration testbench.
3. Load simple hex programs from `programs/hex/` and compare final register or memory state against expected results.
4. Fix any compile/lint issues found by the first real simulator run.
