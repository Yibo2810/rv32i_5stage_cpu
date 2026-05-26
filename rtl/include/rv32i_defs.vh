`ifndef RV32I_DEFS_VH
`define RV32I_DEFS_VH

// Common widths
`define RV32I_XLEN        32
`define RV32I_REG_ADDR_W   5

// Opcodes
`define RV32I_OPCODE_R_TYPE  7'b0110011
`define RV32I_OPCODE_I_TYPE  7'b0010011
`define RV32I_OPCODE_LOAD    7'b0000011
`define RV32I_OPCODE_STORE   7'b0100011
`define RV32I_OPCODE_BRANCH  7'b1100011

// funct3 - ALU register/immediate operations
`define RV32I_FUNCT3_ADD_SUB   3'b000
`define RV32I_FUNCT3_ADDI      3'b000
`define RV32I_FUNCT3_SLL       3'b001
`define RV32I_FUNCT3_SLLI      3'b001
`define RV32I_FUNCT3_SLT       3'b010
`define RV32I_FUNCT3_SLTI      3'b010
`define RV32I_FUNCT3_SLTU      3'b011
`define RV32I_FUNCT3_SLTIU     3'b011
`define RV32I_FUNCT3_XOR       3'b100
`define RV32I_FUNCT3_XORI      3'b100
`define RV32I_FUNCT3_SRL       3'b101
`define RV32I_FUNCT3_SRA       3'b101
`define RV32I_FUNCT3_SRLI      3'b101
`define RV32I_FUNCT3_SRAI      3'b101
`define RV32I_FUNCT3_OR        3'b110
`define RV32I_FUNCT3_ORI       3'b110
`define RV32I_FUNCT3_AND       3'b111
`define RV32I_FUNCT3_ANDI      3'b111

// funct3 - memory/branch operations
`define RV32I_FUNCT3_LW        3'b010
`define RV32I_FUNCT3_SW        3'b010
`define RV32I_FUNCT3_BEQ       3'b000

// funct7 - R-type and shift-immediate operations
`define RV32I_FUNCT7_ADD       7'b0000000
`define RV32I_FUNCT7_SUB       7'b0100000
`define RV32I_FUNCT7_SLL       7'b0000000
`define RV32I_FUNCT7_SLT       7'b0000000
`define RV32I_FUNCT7_SLTU      7'b0000000
`define RV32I_FUNCT7_XOR       7'b0000000
`define RV32I_FUNCT7_SRL       7'b0000000
`define RV32I_FUNCT7_SRA       7'b0100000
`define RV32I_FUNCT7_OR        7'b0000000
`define RV32I_FUNCT7_AND       7'b0000000
`define RV32I_FUNCT7_SLLI      7'b0000000
`define RV32I_FUNCT7_SRLI      7'b0000000
`define RV32I_FUNCT7_SRAI      7'b0100000

// ALU control
`define RV32I_ALU_ADD        4'b0000
`define RV32I_ALU_SUB        4'b0001
`define RV32I_ALU_AND        4'b0010
`define RV32I_ALU_OR         4'b0011
`define RV32I_ALU_XOR        4'b0100
`define RV32I_ALU_SLT        4'b0101
`define RV32I_ALU_SLTU       4'b0110
`define RV32I_ALU_SLL        4'b0111
`define RV32I_ALU_SRL        4'b1000
`define RV32I_ALU_SRA        4'b1001

// Immediate select
`define RV32I_IMM_NONE       3'b000
`define RV32I_IMM_I          3'b001
`define RV32I_IMM_S          3'b010
`define RV32I_IMM_B          3'b011
`define RV32I_IMM_U          3'b100
`define RV32I_IMM_J          3'b101

// Writeback select
`define RV32I_WB_ALU         1'b0
`define RV32I_WB_MEM         1'b1

`endif