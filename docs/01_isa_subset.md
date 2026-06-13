# ISA Subset

This document tracks the RV32I subset currently implemented and verified by the
single-cycle CPU milestone.

## v0.2.0 R/I Direct-Test Coverage

The following instructions are self-checked through the combined
`control_unit`, `imm_gen`, and `alu` path in `tb/sv/ri_execute_tb.sv`:

| Group | Instructions | Verification level |
|---|---|---|
| R arithmetic | `add`, `sub` | Decode/immediate/execute direct test |
| R logical | `and`, `or`, `xor` | Decode/immediate/execute direct test |
| R compare | `slt`, `sltu` | Decode/immediate/execute direct test |
| R shift | `sll`, `srl`, `sra` | Decode/immediate/execute direct test |
| I arithmetic/logical | `addi`, `andi`, `ori`, `xori` | Decode/immediate/execute direct test |
| I compare | `slti`, `sltiu` | Decode/immediate/execute direct test |
| I shift | `slli`, `srli`, `srai` | Decode/immediate/execute direct test |

Each case encodes an instruction, checks the decoded control outputs and
immediate, computes a reference result, and compares it with the ALU result.

This is not yet complete-core integration coverage. Except for the v0.1 subset
below, these instructions still need assembly programs that exercise register
read/write, PC sequencing, memory interaction, and writeback through the whole
single-cycle core.

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

## Deferred After v0.2.0

The following RV32I groups remain deferred:

- Other branches such as `bne`, `blt`, `bge`, `bltu`, and `bgeu`.
- Jumps such as `jal` and `jalr`.
- Upper-immediate instructions such as `lui` and `auipc`.
- Byte/halfword and signed/unsigned load variants and byte/halfword stores.
- CSR, trap, interrupt, and privileged behavior.

The R/I operations listed above also remain pending at complete-core integration
level even though their decode-to-execute direct tests pass.
