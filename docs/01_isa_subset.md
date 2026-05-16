# ISA Subset

This document tracks the first RV32I subset targeted by the single-cycle CPU milestone.

The status below means "RTL datapath/control path exists locally" rather than "fully verified". Functional verification is still pending until the ideal memory and self-checking testbench are added.

## Initial Single-Cycle Subset

| Instruction | Type | RTL status | Main datapath effect |
|---|---|---|---|
| `add` | R | Implemented, TB pending | `rd = rs1 + rs2` |
| `sub` | R | Implemented, TB pending | `rd = rs1 - rs2` |
| `addi` | I | Implemented, TB pending | `rd = rs1 + imm_i` |
| `lw` | I | Implemented, ideal memory/TB pending | `rd = data_memory[rs1 + imm_i]` |
| `sw` | S | Implemented, ideal memory/TB pending | `data_memory[rs1 + imm_s] = rs2` |
| `beq` | B | Implemented, TB pending | `if (rs1 == rs2) pc = pc + imm_b` |

## Not In The First Milestone

The following RV32I groups are intentionally deferred until the first single-cycle subset is runnable and tested:

- Other R/I-type logic instructions such as `and`, `or`, `xor`, `slt`, and their immediate forms.
- Other branches such as `bne`, `blt`, and `bge`.
- Jumps such as `jal` and `jalr`.
- Upper-immediate instructions such as `lui` and `auipc`.
- Byte/halfword loads and stores.
