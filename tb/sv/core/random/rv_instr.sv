import rv_random_pkg::*;

class rv_instr;
    rand instr_kind_e kind;
    rand logic [4:0]  rd, rs1, rs2;
    rand logic [11:0] imm12;
    rand logic [4:0]  shamt;

    constraint legal_regs_c {
        rd  inside {[0:31]};
        rs1 inside {[0:31]};
        rs2 inside {[0:31]};
    }

    constraint supported_kind_c {
        kind inside {
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
        INSTR_EBREAK};
    }

        // ------------------------------------------------------------------
    // 集中映射表:instr_kind -> {format, opcode, funct3, funct7}
    // 这是唯一真相来源。imm 统一传 32 位,每个 packer 自己切自己要的位:
    //   - I/S 用 imm[11:0]
    //   - shift 用 imm[4:0] 当 shamt
    //   - B   用 imm[12:0]
    //   - J   用 imm[20:0]
    //   - U   用 imm[31:12]
    // ------------------------------------------------------------------
    function automatic logic [31:0] encode(
        input instr_kind_e kind,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [31:0] imm
    );
        case (kind)
            // -------- R-type (OP) --------
            INSTR_ADD : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b000, rd);
            INSTR_SUB : return encode_r(OPCODE_R_TYPE, 7'b0100000, rs2, rs1, 3'b000, rd);
            INSTR_SLL : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b001, rd);
            INSTR_SLT : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b010, rd);
            INSTR_SLTU: return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b011, rd);
            INSTR_XOR : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b100, rd);
            INSTR_SRL : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b101, rd);
            INSTR_SRA : return encode_r(OPCODE_R_TYPE, 7'b0100000, rs2, rs1, 3'b101, rd);
            INSTR_OR  : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b110, rd);
            INSTR_AND : return encode_r(OPCODE_R_TYPE, 7'b0000000, rs2, rs1, 3'b111, rd);

            INSTR_ADDI : return encode_i(OPCODE_I_TYPE, imm[11:0], rs1, 3'b000, rd);
            INSTR_SLTI : return encode_i(OPCODE_I_TYPE, imm[11:0], rs1, 3'b010, rd);
            INSTR_SLTIU: return encode_i(OPCODE_I_TYPE, imm[11:0], rs1, 3'b011, rd);
            INSTR_XORI : return encode_i(OPCODE_I_TYPE, imm[11:0], rs1, 3'b100, rd);
            INSTR_ORI  : return encode_i(OPCODE_I_TYPE, imm[11:0], rs1, 3'b110, rd);
            INSTR_ANDI : return encode_i(OPCODE_I_TYPE, imm[11:0], rs1, 3'b111, rd);

            INSTR_SLLI : return encode_i(OPCODE_I_TYPE, {7'b0000000, imm[4:0]}, rs1, 3'b001, rd);
            INSTR_SRLI : return encode_i(OPCODE_I_TYPE, {7'b0000000, imm[4:0]}, rs1, 3'b101, rd);
            INSTR_SRAI : return encode_i(OPCODE_I_TYPE, {7'b0100000, imm[4:0]}, rs1, 3'b101, rd);

            INSTR_LB  : return encode_i(OPCODE_LOAD, imm[11:0], rs1, 3'b000, rd);
            INSTR_LH  : return encode_i(OPCODE_LOAD, imm[11:0], rs1, 3'b001, rd);
            INSTR_LW  : return encode_i(OPCODE_LOAD, imm[11:0], rs1, 3'b010, rd);
            INSTR_LBU : return encode_i(OPCODE_LOAD, imm[11:0], rs1, 3'b100, rd);
            INSTR_LHU : return encode_i(OPCODE_LOAD, imm[11:0], rs1, 3'b101, rd);

            INSTR_SB  : return encode_s(OPCODE_STORE, imm[11:0], rs2, rs1, 3'b000);
            INSTR_SH  : return encode_s(OPCODE_STORE, imm[11:0], rs2, rs1, 3'b001);
            INSTR_SW  : return encode_s(OPCODE_STORE, imm[11:0], rs2, rs1, 3'b010);

            INSTR_BEQ : return encode_b(OPCODE_BRANCH, imm[12:0], rs2, rs1, 3'b000);
            INSTR_BNE : return encode_b(OPCODE_BRANCH, imm[12:0], rs2, rs1, 3'b001);
            INSTR_BLT : return encode_b(OPCODE_BRANCH, imm[12:0], rs2, rs1, 3'b100);
            INSTR_BGE : return encode_b(OPCODE_BRANCH, imm[12:0], rs2, rs1, 3'b101);
            INSTR_BLTU: return encode_b(OPCODE_BRANCH, imm[12:0], rs2, rs1, 3'b110);
            INSTR_BGEU: return encode_b(OPCODE_BRANCH, imm[12:0], rs2, rs1, 3'b111);

            INSTR_JAL : return encode_j(OPCODE_JAL,  imm[20:0], rd);
            INSTR_JALR: return encode_i(OPCODE_JALR, imm[11:0], rs1, 3'b000, rd);

            INSTR_LUI  : return encode_u(OPCODE_LUI,   imm[31:12], rd);
            INSTR_AUIPC: return encode_u(OPCODE_AUIPC, imm[31:12], rd);

            INSTR_ECALL : return encode_i(OPCODE_SYSTEM, 12'h000, 5'd0, 3'b000, 5'd0);
            INSTR_EBREAK: return encode_i(OPCODE_SYSTEM, 12'h001, 5'd0, 3'b000, 5'd0);

            default: return 32'h0000_0013;
        endcase
    endfunction
endclass
