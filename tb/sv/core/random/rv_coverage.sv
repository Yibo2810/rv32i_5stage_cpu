module rv_coverage (
    core_mem_if.monitor mem
);
    import single_pkg::*;
    import rv_random_pkg::*;

    int unsigned program_bytes;

    task automatic set_program_bytes(input int unsigned nbytes);
        program_bytes = nbytes;
    endtask

    function automatic bit in_program(input logic [31:0] pc);
        return (pc[1:0] == 2'b00) && (pc < program_bytes);
    endfunction

    function automatic int decode_kind(input logic [31:0] instr);
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [6:0] funct7;

        opcode = instr[6:0];
        funct3 = instr[14:12];
        funct7 = instr[31:25];

        case (opcode)
            OPCODE_R_TYPE: begin
                case (funct3)
                    FUNCT3_ADD_SUB: begin
                        if (funct7 == FUNCT7_ADD) return INSTR_ADD;
                        if (funct7 == FUNCT7_SUB) return INSTR_SUB;
                        return -1;
                    end
                    FUNCT3_SLL:  return (funct7 == FUNCT7_SLL)  ? INSTR_SLL  : -1;
                    FUNCT3_SLT:  return (funct7 == FUNCT7_SLT)  ? INSTR_SLT  : -1;
                    FUNCT3_SLTU: return (funct7 == FUNCT7_SLTU) ? INSTR_SLTU : -1;
                    FUNCT3_XOR:  return (funct7 == FUNCT7_XOR)  ? INSTR_XOR  : -1;
                    FUNCT3_SRL: begin
                        if (funct7 == FUNCT7_SRL) return INSTR_SRL;
                        if (funct7 == FUNCT7_SRA) return INSTR_SRA;
                        return -1;
                    end
                    FUNCT3_OR:  return (funct7 == FUNCT7_OR)  ? INSTR_OR  : -1;
                    FUNCT3_AND: return (funct7 == FUNCT7_AND) ? INSTR_AND : -1;
                    default:    return -1;
                endcase
            end

            OPCODE_I_TYPE: begin
                case (funct3)
                    FUNCT3_ADDI:  return INSTR_ADDI;
                    FUNCT3_SLTI:  return INSTR_SLTI;
                    FUNCT3_SLTIU: return INSTR_SLTIU;
                    FUNCT3_XORI:  return INSTR_XORI;
                    FUNCT3_ORI:   return INSTR_ORI;
                    FUNCT3_ANDI:  return INSTR_ANDI;
                    FUNCT3_SLLI:  return (funct7 == FUNCT7_SLLI) ? INSTR_SLLI : -1;
                    FUNCT3_SRLI: begin
                        if (funct7 == FUNCT7_SRLI) return INSTR_SRLI;
                        if (funct7 == FUNCT7_SRAI) return INSTR_SRAI;
                        return -1;
                    end
                    default: return -1;
                endcase
            end

            OPCODE_LOAD: begin
                case (funct3)
                    FUNCT3_LB:  return INSTR_LB;
                    FUNCT3_LH:  return INSTR_LH;
                    FUNCT3_LW:  return INSTR_LW;
                    FUNCT3_LBU: return INSTR_LBU;
                    FUNCT3_LHU: return INSTR_LHU;
                    default:    return -1;
                endcase
            end

            OPCODE_STORE: begin
                case (funct3)
                    FUNCT3_SB: return INSTR_SB;
                    FUNCT3_SH: return INSTR_SH;
                    FUNCT3_SW: return INSTR_SW;
                    default:   return -1;
                endcase
            end

            OPCODE_BRANCH: begin
                case (funct3)
                    FUNCT3_BEQ:  return INSTR_BEQ;
                    FUNCT3_BNE:  return INSTR_BNE;
                    FUNCT3_BLT:  return INSTR_BLT;
                    FUNCT3_BGE:  return INSTR_BGE;
                    FUNCT3_BLTU: return INSTR_BLTU;
                    FUNCT3_BGEU: return INSTR_BGEU;
                    default:     return -1;
                endcase
            end

            OPCODE_JAL:   return INSTR_JAL;
            OPCODE_JALR:  return (funct3 == FUNCT3_JALR) ? INSTR_JALR : -1;
            OPCODE_LUI:   return INSTR_LUI;
            OPCODE_AUIPC: return INSTR_AUIPC;

            default: return -1;
        endcase
    endfunction

    function automatic logic [31:0] decode_b_imm(input logic [31:0] instr);
        return {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    endfunction

    function automatic bit is_branch_kind(input int kind);
        return kind inside {
            INSTR_BEQ, INSTR_BNE, INSTR_BLT,
            INSTR_BGE, INSTR_BLTU, INSTR_BGEU
        };
    endfunction

    covergroup cg_branch with function sample(
        int kind,
        bit taken,
        bit backward
    );
        option.per_instance = 1;

        cp_branch_kind: coverpoint kind {
            bins beq  = {INSTR_BEQ};
            bins bne  = {INSTR_BNE};
            bins blt  = {INSTR_BLT};
            bins bge  = {INSTR_BGE};
            bins bltu = {INSTR_BLTU};
            bins bgeu = {INSTR_BGEU};
            illegal_bins non_branch = default;
        }

        cp_branch_taken: coverpoint taken {
            bins not_taken = {1'b0};
            bins taken     = {1'b1};
        }

        cp_branch_dir: coverpoint backward {
            bins forward  = {1'b0};
            bins backward = {1'b1};
        }

        cx_branch_dir_taken: cross cp_branch_dir, cp_branch_taken {
            bins forward_not_taken  = binsof(cp_branch_dir.forward)  && binsof(cp_branch_taken.not_taken);
            bins forward_taken      = binsof(cp_branch_dir.forward)  && binsof(cp_branch_taken.taken);
            bins backward_not_taken = binsof(cp_branch_dir.backward) && binsof(cp_branch_taken.not_taken);
            bins backward_taken     = binsof(cp_branch_dir.backward) && binsof(cp_branch_taken.taken);
        }
    endgroup

    covergroup cg_mem with function sample(
        int kind,
        bit is_read,
        bit is_write,
        logic [1:0] addr_off,
        logic [3:0] wstrb,
        logic [31:0] rdata
    );
        option.per_instance = 1;

        cp_mem_kind: coverpoint kind {
            bins instr_lb  = {INSTR_LB};
            bins instr_lh  = {INSTR_LH};
            bins instr_lw  = {INSTR_LW};
            bins instr_lbu = {INSTR_LBU};
            bins instr_lhu = {INSTR_LHU};

            bins instr_sb = {INSTR_SB};
            bins instr_sh = {INSTR_SH};
            bins instr_sw = {INSTR_SW};

            illegal_bins non_mem = default;
        }

        cp_store_wstrb: coverpoint wstrb iff (is_write) {
            bins sb_lane0 = {4'b0001};
            bins sb_lane1 = {4'b0010};
            bins sb_lane2 = {4'b0100};
            bins sb_lane3 = {4'b1000};

            bins sh_low   = {4'b0011};
            bins sh_high  = {4'b1100};

            bins sw_word  = {4'b1111};

            illegal_bins bad_wstrb = default;
        }

        cp_byte_load_offset: coverpoint addr_off
            iff (is_read && ((kind == INSTR_LB) || (kind == INSTR_LBU))) {
            bins off0 = {2'd0};
            bins off1 = {2'd1};
            bins off2 = {2'd2};
            bins off3 = {2'd3};
        }

        cp_half_load_offset: coverpoint addr_off
            iff (is_read && ((kind == INSTR_LH) || (kind == INSTR_LHU))) {
            bins off0 = {2'd0};
            bins off2 = {2'd2};
            ignore_bins misaligned = {2'd1, 2'd3};
        }

        cp_word_load_offset: coverpoint addr_off
            iff (is_read && (kind == INSTR_LW)) {
            bins off0 = {2'd0};
            ignore_bins misaligned = {2'd1, 2'd2, 2'd3};
        }

        cp_load_data_nonzero: coverpoint (rdata != 32'b0) iff (is_read) {
            bins zero    = {1'b0};
            bins nonzero = {1'b1};
        }
    endgroup

    covergroup cg_instr with function sample(logic [6:0] opcode, int kind);
        option.per_instance = 1;

        cp_opcode: coverpoint opcode {
            bins r_type = {OPCODE_R_TYPE};
            bins i_type = {OPCODE_I_TYPE};
            bins load   = {OPCODE_LOAD};
            bins store  = {OPCODE_STORE};
            bins branch = {OPCODE_BRANCH};
            bins jal    = {OPCODE_JAL};
            bins jalr   = {OPCODE_JALR};
            bins lui    = {OPCODE_LUI};
            bins auipc  = {OPCODE_AUIPC};
            illegal_bins illegal = default;
        }

        cp_kind: coverpoint kind {
            bins instr_add  = {INSTR_ADD};
            bins instr_sub  = {INSTR_SUB};
            bins instr_and  = {INSTR_AND};
            bins instr_or   = {INSTR_OR};
            bins instr_xor  = {INSTR_XOR};
            bins instr_sll  = {INSTR_SLL};
            bins instr_srl  = {INSTR_SRL};
            bins instr_sra  = {INSTR_SRA};
            bins instr_slt  = {INSTR_SLT};
            bins instr_sltu = {INSTR_SLTU};

            bins instr_addi  = {INSTR_ADDI};
            bins instr_andi  = {INSTR_ANDI};
            bins instr_ori   = {INSTR_ORI};
            bins instr_xori  = {INSTR_XORI};
            bins instr_slli  = {INSTR_SLLI};
            bins instr_srli  = {INSTR_SRLI};
            bins instr_srai  = {INSTR_SRAI};
            bins instr_slti  = {INSTR_SLTI};
            bins instr_sltiu = {INSTR_SLTIU};

            bins instr_lb  = {INSTR_LB};
            bins instr_lh  = {INSTR_LH};
            bins instr_lw  = {INSTR_LW};
            bins instr_lbu = {INSTR_LBU};
            bins instr_lhu = {INSTR_LHU};

            bins instr_sb = {INSTR_SB};
            bins instr_sh = {INSTR_SH};
            bins instr_sw = {INSTR_SW};

            bins instr_beq  = {INSTR_BEQ};
            bins instr_bne  = {INSTR_BNE};
            bins instr_blt  = {INSTR_BLT};
            bins instr_bge  = {INSTR_BGE};
            bins instr_bltu = {INSTR_BLTU};
            bins instr_bgeu = {INSTR_BGEU};

            bins instr_jal   = {INSTR_JAL};
            bins instr_jalr  = {INSTR_JALR};
            bins instr_lui   = {INSTR_LUI};
            bins instr_auipc = {INSTR_AUIPC};

            illegal_bins unknown = {-1};
        }
    endgroup

    cg_instr instr_cov;
    cg_mem   mem_cov;
    cg_branch branch_cov;

    bit          prev_branch_valid;
    int          prev_branch_kind;
    logic [31:0] prev_branch_pc;
    logic [31:0] prev_branch_imm;

    initial begin
        instr_cov = new();
        mem_cov   = new();
        branch_cov = new();
        prev_branch_valid = 1'b0;
    end

    always @(mem.cb) begin
        if (mem.cb.rst) begin
            prev_branch_valid = 1'b0;
        end
        else if (in_program(mem.cb.imem_addr)) begin
            int kind;
            bit prev_taken;
            bit prev_backward;

            if (prev_branch_valid) begin
                prev_taken    = (mem.cb.imem_addr == (prev_branch_pc + prev_branch_imm));
                prev_backward = ($signed(prev_branch_imm) < 0);
                branch_cov.sample(prev_branch_kind, prev_taken, prev_backward);
            end

            kind = decode_kind(mem.cb.imem_rdata);
            instr_cov.sample(mem.cb.imem_rdata[6:0], kind);

            prev_branch_valid = is_branch_kind(kind);
            if (prev_branch_valid) begin
                prev_branch_kind = kind;
                prev_branch_pc   = mem.cb.imem_addr;
                prev_branch_imm  = decode_b_imm(mem.cb.imem_rdata);
            end

            if (mem.cb.dmem_read || mem.cb.dmem_write) begin
                mem_cov.sample(
                    kind,
                    mem.cb.dmem_read,
                    mem.cb.dmem_write,
                    mem.cb.dmem_addr[1:0],
                    mem.cb.dmem_wstrb,
                    mem.cb.dmem_rdata
                );
            end
        end
        else begin
            prev_branch_valid = 1'b0;
        end
    end
    final begin
        $display("RV_INSTR_COVERAGE  = %0.2f%%", instr_cov.get_inst_coverage());
        $display("RV_OPCODE_COVERAGE = %0.2f%%", instr_cov.cp_opcode.get_inst_coverage());
        $display("RV_KIND_COVERAGE   = %0.2f%%", instr_cov.cp_kind.get_inst_coverage());
        $display("RV_MEM_COVERAGE    = %0.2f%%", mem_cov.get_inst_coverage());
        $display("RV_BRANCH_COVERAGE = %0.2f%%", branch_cov.get_inst_coverage());
    end
endmodule
