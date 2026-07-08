class rv_instr;
    rand instr_kind_e kind;
    rand logic [4:0]  rd, rs1, rs2;
    rand logic [31:0] imm32;
    bit locked = 1'b0;

    constraint legal_regs_c {
        rd  inside {[0:31]};
        rs1 inside {[0:31]};
        rs2 inside {[0:31]};
    }

    constraint reserve_counter_c { rd != 5'd31; }

    constraint supported_kind_c {
        kind inside {
        INSTR_ADD, INSTR_SUB, INSTR_AND, INSTR_OR, INSTR_XOR, INSTR_SLL,
        INSTR_SRL, INSTR_SRA, INSTR_SLT, INSTR_SLTU, INSTR_ADDI, INSTR_ANDI,
        INSTR_ORI, INSTR_XORI, INSTR_SLLI, INSTR_SRLI, INSTR_SRAI, INSTR_SLTI,
        INSTR_SLTIU, INSTR_LB, INSTR_LH, INSTR_LW, INSTR_LBU, INSTR_LHU, INSTR_SB, INSTR_SH,
        INSTR_SW, INSTR_BEQ, INSTR_BNE, INSTR_BLT, INSTR_BGE, INSTR_BLTU, INSTR_BGEU, INSTR_JAL,
        INSTR_JALR, INSTR_LUI, INSTR_AUIPC};
    }
    constraint mem_safe_c {
        (kind inside {INSTR_LB, INSTR_LH, INSTR_LW, INSTR_LBU, INSTR_LHU, INSTR_SB, INSTR_SH,
        INSTR_SW}) -> {
            rs1 == 5'd0;
            imm32 inside {[0:508]};
        }

        (kind inside {INSTR_LH, INSTR_LHU, INSTR_SH}) -> imm32[0] == 1'b0;
        (kind inside {INSTR_LW, INSTR_SW}) -> imm32[1:0] == 2'b00;
    }

    constraint kind_dist_c{
        kind dist { [INSTR_ADD:INSTR_SLTU] :/ 20, [INSTR_ADDI:INSTR_SLTIU] :/ 20, [INSTR_LB:INSTR_LHU] :/ 10,
                    [INSTR_SB:INSTR_SW] :/ 10, [INSTR_LUI:INSTR_AUIPC] :/ 10};
    }

    function automatic logic [31:0] encode();
        case (kind)
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

            INSTR_ADDI : return encode_i(OPCODE_I_TYPE, imm32[11:0], rs1, 3'b000, rd);
            INSTR_SLTI : return encode_i(OPCODE_I_TYPE, imm32[11:0], rs1, 3'b010, rd);
            INSTR_SLTIU: return encode_i(OPCODE_I_TYPE, imm32[11:0], rs1, 3'b011, rd);
            INSTR_XORI : return encode_i(OPCODE_I_TYPE, imm32[11:0], rs1, 3'b100, rd);
            INSTR_ORI  : return encode_i(OPCODE_I_TYPE, imm32[11:0], rs1, 3'b110, rd);
            INSTR_ANDI : return encode_i(OPCODE_I_TYPE, imm32[11:0], rs1, 3'b111, rd);

            INSTR_SLLI : return encode_i(OPCODE_I_TYPE, {7'b0000000, imm32[4:0]}, rs1, 3'b001, rd);
            INSTR_SRLI : return encode_i(OPCODE_I_TYPE, {7'b0000000, imm32[4:0]}, rs1, 3'b101, rd);
            INSTR_SRAI : return encode_i(OPCODE_I_TYPE, {7'b0100000, imm32[4:0]}, rs1, 3'b101, rd);

            INSTR_LB  : return encode_i(OPCODE_LOAD, imm32[11:0], rs1, 3'b000, rd);
            INSTR_LH  : return encode_i(OPCODE_LOAD, imm32[11:0], rs1, 3'b001, rd);
            INSTR_LW  : return encode_i(OPCODE_LOAD, imm32[11:0], rs1, 3'b010, rd);
            INSTR_LBU : return encode_i(OPCODE_LOAD, imm32[11:0], rs1, 3'b100, rd);
            INSTR_LHU : return encode_i(OPCODE_LOAD, imm32[11:0], rs1, 3'b101, rd);

            INSTR_SB  : return encode_s(OPCODE_STORE, imm32[11:0], rs2, rs1, 3'b000);
            INSTR_SH  : return encode_s(OPCODE_STORE, imm32[11:0], rs2, rs1, 3'b001);
            INSTR_SW  : return encode_s(OPCODE_STORE, imm32[11:0], rs2, rs1, 3'b010);

            INSTR_BEQ : return encode_b(OPCODE_BRANCH, imm32[12:0], rs2, rs1, 3'b000);
            INSTR_BNE : return encode_b(OPCODE_BRANCH, imm32[12:0], rs2, rs1, 3'b001);
            INSTR_BLT : return encode_b(OPCODE_BRANCH, imm32[12:0], rs2, rs1, 3'b100);
            INSTR_BGE : return encode_b(OPCODE_BRANCH, imm32[12:0], rs2, rs1, 3'b101);
            INSTR_BLTU: return encode_b(OPCODE_BRANCH, imm32[12:0], rs2, rs1, 3'b110);
            INSTR_BGEU: return encode_b(OPCODE_BRANCH, imm32[12:0], rs2, rs1, 3'b111);

            INSTR_JAL : return encode_j(OPCODE_JAL,  imm32[20:0], rd);
            INSTR_JALR: return encode_i(OPCODE_JALR, imm32[11:0], rs1, 3'b000, rd);

            INSTR_LUI  : return encode_u(OPCODE_LUI,   imm32[31:12], rd);
            INSTR_AUIPC: return encode_u(OPCODE_AUIPC, imm32[31:12], rd);

            INSTR_ECALL : return encode_i(OPCODE_SYSTEM, 12'h000, 5'd0, 3'b000, 5'd0);
            INSTR_EBREAK: return encode_i(OPCODE_SYSTEM, 12'h001, 5'd0, 3'b000, 5'd0);

            default: return 32'h0000_0013;
        endcase
    endfunction
endclass
