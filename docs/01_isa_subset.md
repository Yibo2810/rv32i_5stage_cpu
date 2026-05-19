# ISA Subset

This document tracks the RV32I subset currently implemented and verified by the
single-cycle CPU milestone.

## v0.1 Verified Single-Cycle Subset

The status below means the instruction has an RTL path and is covered by the
current directed self-checking single-cycle tests.

| Instruction | Type | v0.1 status | Main datapath effect |
|---|---|---|---|
| `add` | R | Verified by `add_test` | `rd = rs1 + rs2` |
| `sub` | R | Verified by `sub_test` | `rd = rs1 - rs2` |
| `addi` | I | Verified through all current programs | `rd = rs1 + imm_i` |
| `lw` | I | Verified by `load_store_test` | `rd = data_memory[rs1 + imm_i]` |
| `sw` | S | Verified by all current signature tests | `data_memory[rs1 + imm_s] = rs2` |
| `beq` | B | Verified by `branch_test` | `if (rs1 == rs2) pc = pc + imm_b` |

## Current Test Signatures

| Test | Main instructions exercised | Expected signature |
|---|---|---|
| `add_test` | `addi`, `add`, `sw` | `dmem[0] = 12` |
| `sub_test` | `addi`, `sub`, `sw` | `dmem[0] = 5` |
| `load_store_test` | `addi`, `sw`, `lw` | `dmem[1] = 42` |
| `branch_test` | `addi`, `beq`, `sw` | `dmem[0] = 1` |

## Not In The v0.1 Milestone

The following RV32I groups are intentionally deferred:

- Other R/I-type logic instructions such as `and`, `or`, `xor`, `slt`, and their immediate forms.
- Shift instructions such as `sll`, `srl`, `sra`, `slli`, `srli`, and `srai`.
- Other branches such as `bne`, `blt`, `bge`, `bltu`, and `bgeu`.
- Jumps such as `jal` and `jalr`.
- Upper-immediate instructions such as `lui` and `auipc`.
- Byte/halfword loads and stores.
- CSR, trap, interrupt, and privileged behavior.

These will be added in later single-cycle expansion phases before the project
moves into the five-stage pipeline.
