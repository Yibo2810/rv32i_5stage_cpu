# Project Plan

## Goals

- Build a minimal RV32I single-cycle CPU.
- Verify correctness with focused assembly programs and self-checking testbenches.
- Extend the design to a five-stage pipeline after the single-cycle baseline is stable.

## Current Milestone

The project has reached **v0.2.0 SystemVerilog R/I direct verification**.

This milestone preserves the v0.1 single-cycle assembly regression and adds a
SystemVerilog direct test for the R/I decode-to-execute path. The direct test
checks `control_unit`, `imm_gen`, and `alu` for:

```text
add, sub, and, or, xor, slt, sltu, sll, srl, sra
addi, andi, ori, xori, slti, sltiu, slli, srli, srai
```

The complete-core integration regression remains scoped to `add`, `sub`, `addi`,
`lw`, `sw`, and `beq`. v0.2.0 therefore expands module-level verification
without claiming full CPU-level R/I verification or pipeline behavior.

## Milestones

| Phase | Milestone | Status |
|---|---|---|
| 0 | Repository structure and learning-oriented documentation scaffold | Done |
| 1 | Minimal ISA subset and single-cycle RTL modules | Done for v0.1 subset |
| 2 | Ideal instruction/data memory and self-checking single-cycle testbench | Done |
| 3 | Directed single-cycle programs and result checking | Done for v0.1 subset |
| 4 | SystemVerilog conversion and R/I direct module-path verification | Done for v0.2.0 |
| 5 | Branch and load/store variant verification | Next |
| 6 | Add stronger verification: x0/reset/alignment tests, assertions, and coverage | Planned |
| 7 | Five-stage pipeline partitioning | Planned |
| 8 | Hazard detection, forwarding, stall, and flush logic | Planned |
| 9 | Regression scripts and broader verification | Planned |

## Immediate Next Work

1. Add branch variants with taken and not-taken cases.
2. Add load/store width and signedness variants.
3. Refactor the oversized R/I direct test into reusable verification helpers.
4. Add complete-core programs for the newly verified R/I operations.
5. Add directed tests for x0, reset, illegal instructions, and alignment.
6. Keep GitHub Actions running the Verilator regression on every push.
