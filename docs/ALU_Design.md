## ALU Design

The ALU performs arithmetic operations selected by `alu_ctrl`.

In the first single-cycle milestone, the ALU only needs to support:

| ALU Control | Operation | Used By |
|---|---|---|
| `ALU_ADD` | `src_a + src_b` | `add`, `addi`, `lw`, `sw` |
| `ALU_SUB` | `src_a - src_b` | `sub`, `beq` |

The ALU does not decode full RISC-V instructions. Instruction decoding is handled by the control unit. The control unit selects the ALU operation and chooses whether the second ALU input comes from `rs2_data` or an immediate.

### ALU Interface

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `src_a` | input | 32 | First ALU operand, usually `rs1_data` |
| `src_b` | input | 32 | Second ALU operand, either `rs2_data` or immediate |
| `alu_ctrl` | input | 4 | Selects ALU operation |
| `result` | output | 32 | ALU result |
| `zero` | output | 1 | High when `result == 0`, used by `beq` |

### Instruction Mapping

| Instruction | ALU operation | Notes |
|---|---|---|
| `add` | ADD | Register-register addition |
| `sub` | SUB | Register-register subtraction |
| `addi` | ADD | Immediate addition |
| `lw` | ADD | Address calculation |
| `sw` | ADD | Address calculation |
| `beq` | SUB | If subtraction result is zero, branch is taken |
