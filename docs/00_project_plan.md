# Project Plan

## Goals

- Build a minimal RV32I single-cycle CPU.
- Verify correctness with focused assembly programs and self-checking testbenches.
- Extend the design to a five-stage pipeline after the single-cycle baseline is stable.

## Current Milestone

The project has reached **v0.1 single-cycle verified subset**.

This milestone verifies a small single-cycle RV32I subset with directed assembly
programs, generated hex files, ideal instruction/data memories, and a
self-checking testbench. The current verified instructions are:

```text
add, sub, addi, lw, sw, beq
```

This milestone is intentionally scoped. It proves the first complete
single-cycle execution loop, but it does not claim full RV32I coverage or
pipeline behavior.

## Milestones

| Phase | Milestone | Status |
|---|---|---|
| 0 | Repository structure and learning-oriented documentation scaffold | Done |
| 1 | Minimal ISA subset and single-cycle RTL modules | Done for v0.1 subset |
| 2 | Ideal instruction/data memory and self-checking single-cycle testbench | Done |
| 3 | Directed single-cycle programs and result checking | Done for v0.1 subset |
| 4 | Expand single-cycle RV32I instruction coverage | Next |
| 5 | Add stronger verification: x0/reset/alignment tests, assertions, and coverage | Planned |
| 6 | Five-stage pipeline partitioning | Planned |
| 7 | Hazard detection, forwarding, stall, and flush logic | Planned |
| 8 | Regression scripts and broader verification | Planned |

## Immediate Next Work

1. Add directed tests for x0 behavior and reset behavior.
2. Expand the single-cycle ISA subset in small groups.
3. Tighten `control_unit` legality checks as new instruction groups are added.
4. Fix U/J immediate generation when `lui`, `auipc`, `jal`, and `jalr` enter scope.
5. Keep GitHub Actions running the directed single-cycle suite on every push.
