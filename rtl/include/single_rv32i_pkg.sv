package single_pkg;

  // Common widths
  localparam int XLEN       = 32;
  localparam int REG_ADDR_W = 5;

  // Opcodes
  localparam logic [6:0] OPCODE_R_TYPE = 7'b0110011;
  localparam logic [6:0] OPCODE_I_TYPE = 7'b0010011;
  localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
  localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
  localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;

  // funct3 - ALU register/immediate operations
  localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
  localparam logic [2:0] FUNCT3_ADDI    = 3'b000;
  localparam logic [2:0] FUNCT3_SLL     = 3'b001;
  localparam logic [2:0] FUNCT3_SLLI    = 3'b001;
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
  localparam logic [2:0] FUNCT3_LW  = 3'b010;
  localparam logic [2:0] FUNCT3_SW  = 3'b010;
  localparam logic [2:0] FUNCT3_BEQ = 3'b000;

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

  typedef enum logic {
    WB_ALU = 1'b0,
    WB_MEM = 1'b1
  } wb_sel_e;

endpackage
