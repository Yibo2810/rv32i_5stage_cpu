# Verification Plan

## Current Verification Status

The single-cycle RTL has been implemented as a first-pass local checkpoint, but it has not yet been compile-checked or functionally verified in this repository. The immediate verification goal is to make the single-cycle core runnable with an ideal memory model and a self-checking testbench.

## Test Areas

- Arithmetic and immediate instructions
- Load and store instructions
- Branch behavior for the first supported subset
- Register x0 behavior
- Reset and first-PC behavior
- Data hazards and forwarding
- Load-use stalls
- Pipeline flush behavior

## Single-Cycle Bring-Up Plan

1. Create an ideal memory wrapper for instruction fetch and load/store access.
2. Load small hex programs into instruction memory with `$readmemh`.
3. Drive clock/reset in `tb_single_cycle.v`.
4. Run each program for a fixed maximum cycle count.
5. Check expected final register or data memory values automatically.
6. Print a clear PASS/FAIL result and stop with an error on mismatch.

## First Directed Tests

| Test | Purpose | Expected check |
|---|---|---|
| `add_test` | Check register-register add/sub path | Final register values match expected arithmetic results |
| `addi_test` | Check I-type immediate generation and ALU source mux | Immediate addition writes the expected `rd` |
| `load_store_test` | Check effective address generation and memory write/read | Stored word and loaded word match expected values |
| `branch_test` | Check `beq`, branch immediate, and next-PC selection | Taken and not-taken branch paths land at the expected instructions |
| `x0_test` | Check x0 protection | Writes to x0 do not change its read value |
| `reset_test` | Check initial state | PC starts at zero and registers reset to zero |

## Later Pipeline Verification

Pipeline verification should start only after the single-cycle baseline is runnable. Later test areas include:

- IF/ID/EX/MEM/WB pipeline register behavior
- Forwarding paths
- Load-use stalls
- Branch flush behavior
- Multi-instruction regression programs
