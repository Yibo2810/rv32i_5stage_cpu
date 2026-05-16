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

// funct3
`define RV32I_FUNCT3_ADD_SUB 3'b000
`define RV32I_FUNCT3_ADDI    3'b000
`define RV32I_FUNCT3_LW      3'b010
`define RV32I_FUNCT3_SW      3'b010
`define RV32I_FUNCT3_BEQ     3'b000

// funct7
`define RV32I_FUNCT7_ADD     7'b0000000
`define RV32I_FUNCT7_SUB     7'b0100000

// ALU control
`define RV32I_ALU_ADD        4'b0000
`define RV32I_ALU_SUB        4'b0001

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