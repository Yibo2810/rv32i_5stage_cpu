`timescale 1ns/1ps

package single_pkg;

  // Opcodes
  localparam logic [6:0] OPCODE_R_TYPE = 7'b0110011;
  localparam logic [6:0] OPCODE_I_TYPE = 7'b0010011;
  localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
  localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
  localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
  localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
  localparam logic [6:0] OPCODE_JALR   = 7'b1100111;
  localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
  localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
  localparam logic [6:0] OPCODE_SYSTEM  = 7'b1110011;

  // funct3 - ALU register/immediate operations
  localparam logic [2:0] FUNCT3_ADD_SUB      = 3'b000;
  localparam logic [2:0] FUNCT3_ADDI         = 3'b000;
  localparam logic [2:0] FUNCT3_JALR         = 3'b000;
  localparam logic [2:0] FUNCT3_ECALL_EBREAK = 3'b000;
  localparam logic [2:0] FUNCT3_SLL          = 3'b001;
  localparam logic [2:0] FUNCT3_SLLI         = 3'b001;
  localparam logic [2:0] FUNCT3_SLT     = 3'b010;
  localparam logic [2:0] FUNCT3_SLTI    = 3'b010;
  localparam logic [2:0] FUNCT3_SLTU    = 3'b011;
  localparam logic [2:0] FUNCT3_SLTIU   = 3'b011;
  localparam logic [2:0] FUNCT3_XOR     = 3'b100;
  localparam logic [2:0] FUNCT3_XORI    = 3'b100;
  localparam logic [2:0] FUNCT3_SRL     = 3'b101;
  localparam logic [2:0] FUNCT3_SRA     = 3'b101;
  localparam logic [2:0] FUNCT3_SRLI    = 3'b101;
  localparam logic [2:0] FUNCT3_SRAI    = 3'b101;
  localparam logic [2:0] FUNCT3_OR      = 3'b110;
  localparam logic [2:0] FUNCT3_ORI     = 3'b110;
  localparam logic [2:0] FUNCT3_AND     = 3'b111;
  localparam logic [2:0] FUNCT3_ANDI    = 3'b111;

  // funct3 - memory/branch operations
  localparam logic [2:0] FUNCT3_LB   = 3'b000;
  localparam logic [2:0] FUNCT3_LH   = 3'b001;
  localparam logic [2:0] FUNCT3_LW   = 3'b010;
  localparam logic [2:0] FUNCT3_LBU  = 3'b100;
  localparam logic [2:0] FUNCT3_LHU  = 3'b101;
  localparam logic [2:0] FUNCT3_SB   = 3'b000;
  localparam logic [2:0] FUNCT3_SH   = 3'b001;
  localparam logic [2:0] FUNCT3_SW   = 3'b010;
  localparam logic [2:0] FUNCT3_BEQ  = 3'b000;
  localparam logic [2:0] FUNCT3_BNE  = 3'b001;
  localparam logic [2:0] FUNCT3_BLT  = 3'b100;
  localparam logic [2:0] FUNCT3_BGE  = 3'b101;
  localparam logic [2:0] FUNCT3_BLTU = 3'b110;
  localparam logic [2:0] FUNCT3_BGEU = 3'b111;

  // funct7 - R-type and shift-immediate operations
  localparam logic [6:0] FUNCT7_ADD  = 7'b0000000;
  localparam logic [6:0] FUNCT7_SUB  = 7'b0100000;
  localparam logic [6:0] FUNCT7_SLL  = 7'b0000000;
  localparam logic [6:0] FUNCT7_SLT  = 7'b0000000;
  localparam logic [6:0] FUNCT7_SLTU = 7'b0000000;
  localparam logic [6:0] FUNCT7_XOR  = 7'b0000000;
  localparam logic [6:0] FUNCT7_SRL  = 7'b0000000;
  localparam logic [6:0] FUNCT7_SRA  = 7'b0100000;
  localparam logic [6:0] FUNCT7_OR   = 7'b0000000;
  localparam logic [6:0] FUNCT7_AND  = 7'b0000000;
  localparam logic [6:0] FUNCT7_SLLI = 7'b0000000;
  localparam logic [6:0] FUNCT7_SRLI = 7'b0000000;
  localparam logic [6:0] FUNCT7_SRAI = 7'b0100000;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_AND  = 4'b0010,
    ALU_OR   = 4'b0011,
    ALU_XOR  = 4'b0100,
    ALU_SLT  = 4'b0101,
    ALU_SLTU = 4'b0110,
    ALU_SLL  = 4'b0111,
    ALU_SRL  = 4'b1000,
    ALU_SRA  = 4'b1001
  } alu_ctrl_e;

  typedef enum logic [2:0] {
    IMM_NONE = 3'b000,
    IMM_I    = 3'b001,
    IMM_S    = 3'b010,
    IMM_B    = 3'b011,
    IMM_U    = 3'b100,
    IMM_J    = 3'b101
  } imm_sel_e;

  typedef enum logic [1:0] {
    WB_ALU = 2'b00,
    WB_MEM = 2'b01,
    WB_PC4 = 2'b10
  } wb_sel_e;

  typedef enum logic [1:0] {
    ALU_A_RS1 = 2'b00,
    ALU_A_PC  = 2'b01,
    ALU_A_ZERO= 2'b10
  } alu_src_a_sel_e;

  typedef enum logic [1:0] {
    MEM_BYTE = 2'b00,
    MEM_HALF = 2'b01,
    MEM_WORD = 2'b10
  } mem_size_e;

  typedef enum logic [1:0] {
    PC_TARGET_PC_IMM = 2'b00,
    PC_TARGET_ALU    = 2'b01
  } pc_target_sel_e;

  typedef enum logic [3:0] {
    EXC_INSTR_ADDR_MISALIGNED = 4'd0,
    EXC_ILLEGAL_INSTR         = 4'd2,
    EXC_BREAKPOINT            = 4'd3,
    EXC_LOAD_ADDR_MISALIGNED  = 4'd4,
    EXC_LOAD_ACCESS_FAULT     = 4'd5,
    EXC_STORE_ADDR_MISALIGNED = 4'd6,
    EXC_STORE_ACCESS_FAULT    = 4'd7,
    EXC_ECALL_MMODE           = 4'd11
} exc_cause_e;

  typedef struct packed {
      logic         valid;
      exc_cause_e   cause;
  } exception_t;
endpackage
