# v0.1 Milestone: Single-Cycle Verified Subset

## Summary

v0.1 is the first verified execution milestone for this repository.

It contains a single-cycle RV32I CPU subset implemented in Verilog and verified
with directed assembly programs, generated machine-code hex, ideal memories, and
a self-checking testbench.

## Verified Instructions

```text
add, sub, addi, lw, sw, beq
```

## Verification Evidence

The directed tests are:

| Test | Expected result |
|---|---|
| `add_test` | `dmem[0] = 12` |
| `sub_test` | `dmem[0] = 5` |
| `load_store_test` | `dmem[1] = 42` |
| `branch_test` | `dmem[0] = 1` |

The same flow is run by GitHub Actions in `.github/workflows/rtl.yml`.
The workflow generates hex files, runs the single-cycle simulation, and uploads
logs/waves as artifacts.

## What v0.1 Does Not Claim

- It is not a full RV32I implementation.
- It does not include the five-stage pipeline.
- It does not yet include constrained-random verification, functional coverage,
  or UVM-style infrastructure.
- It uses ideal memory models rather than a realistic bus/cache/memory system.

## Next Phase

The next phase is to expand the single-cycle RV32I subset and strengthen the
verification suite before starting the five-stage pipeline.
