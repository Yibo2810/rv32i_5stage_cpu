package rv_random_pkg;
    typedef enum int {
        INSTR_ADD,
        INSTR_SUB,
        INSTR_AND,
        INSTR_OR,
        INSTR_XOR,
        INSTR_SLL,
        INSTR_SRL,
        INSTR_SRA,
        INSTR_SLT,
        INSTR_SLTU,
        INSTR_ADDI,
        INSTR_ANDI,
        INSTR_ORI,
        INSTR_XORI,
        INSTR_SLLI,
        INSTR_SRLI,
        INSTR_SRAI,
        INSTR_SLTI,
        INSTR_SLTIU,
        INSTR_LB,
        INSTR_LH,
        INSTR_LW,
        INSTR_LBU,
        INSTR_LHU,
        INSTR_SB,
        INSTR_SH,
        INSTR_SW,
        INSTR_BEQ,
        INSTR_BNE,
        INSTR_BLT,
        INSTR_BGE,
        INSTR_BLTU,
        INSTR_BGEU,
        INSTR_JAL,
        INSTR_JALR,
        INSTR_LUI,
        INSTR_AUIPC,
        INSTR_ECALL,
        INSTR_EBREAK
    } instr_kind_e;

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

    function automatic logic [31:0] encode_r(
        input logic [6:0] opcode,
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_i(
        input logic [6:0]  opcode,
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [6:0]  opcode,
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] encode_b(
        input logic [6:0]  opcode,
        input logic [12:0] imm,   // imm[12:1], imm[0] = 0
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] encode_u(
        input logic [6:0]  opcode,
        input logic [19:0] imm,   // imm[31:12]
        input logic [4:0]  rd
    );
        return {imm, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_j(
        input logic [6:0]  opcode,
        input logic [20:0] imm,   // imm[20:1], imm[0] = 0
        input logic [4:0]  rd
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction
endpackage
