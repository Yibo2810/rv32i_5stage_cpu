`timescale 1ns/1ps

import single_pkg::*;

module control_unit(
    input  logic [31:0]   instr,
    output logic          mem_write,
    output logic          mem_read,
    output logic          reg_write,
    output logic          alu_sel_b,
    output wb_sel_e       wb_sel,
    output logic          branch,
    output alu_ctrl_e     alu_ctrl,
    output imm_sel_e      imm_sel,
    output logic          illegal_instr,
    output logic          branch_on_zero,
    output mem_size_e     mem_size,
    output logic          load_unsigned,
    output logic          jump_and_link,
    output alu_src_a_sel_e alu_src_a_sel,
    output pc_target_sel_e pc_target_sel
);
    typedef enum logic [1:0] {
        ALU_OP_ADD    = 2'b00,
        ALU_OP_BRANCH = 2'b01,
        ALU_OP_RTYPE  = 2'b10,
        ALU_OP_ITYPE  = 2'b11
    } alu_op_e;

    alu_op_e    alu_op;
    logic [6:0] opcode;
    logic [6:0] funct7;
    logic [2:0] funct3;
    logic       illegal_main;
    logic       illegal_alu;


    assign opcode = instr[6:0];
    assign funct7 = instr[31:25];
    assign funct3 = instr[14:12];


    always_comb begin
        mem_write    = 1'b0;
        mem_read     = 1'b0;
        reg_write    = 1'b0;
        alu_sel_b    = 1'b0;
        wb_sel       = WB_ALU;
        branch       = 1'b0;
        imm_sel      = IMM_I;
        alu_op       = ALU_OP_ADD;
        mem_size     = MEM_WORD;
        load_unsigned = 1'b0;
        illegal_main = 1'b0;
        jump_and_link = 1'b0;
        alu_src_a_sel = ALU_A_RS1;
        pc_target_sel = PC_TARGET_PC_IMM;

        case (opcode)
            OPCODE_R_TYPE : begin
                reg_write = 1'b1;
                imm_sel   = IMM_NONE;
                wb_sel    = WB_ALU;
                alu_op    = ALU_OP_RTYPE;
            end

            OPCODE_I_TYPE : begin
                reg_write = 1'b1;
                alu_sel_b = 1'b1;
                imm_sel   = IMM_I;
                wb_sel    = WB_ALU;
                alu_op    = ALU_OP_ITYPE;
            end

            OPCODE_BRANCH : begin
                branch  = 1'b1;
                imm_sel = IMM_B;
                alu_op  = ALU_OP_BRANCH;
                wb_sel  = WB_ALU;
                alu_src_a_sel = ALU_A_RS1;
                pc_target_sel = PC_TARGET_PC_IMM;
            end

            OPCODE_LOAD : begin
                reg_write = 1'b1;
                mem_read  = 1'b1;
                alu_sel_b = 1'b1;
                wb_sel    = WB_MEM;
                imm_sel   = IMM_I;
                alu_op    = ALU_OP_ADD;
                case (funct3)
                    FUNCT3_LB : begin mem_size = MEM_BYTE; load_unsigned = 1'b0; end
                    FUNCT3_LH : begin mem_size = MEM_HALF; load_unsigned = 1'b0; end
                    FUNCT3_LW : begin mem_size = MEM_WORD; load_unsigned = 1'b0; end
                    FUNCT3_LBU: begin mem_size = MEM_BYTE; load_unsigned = 1'b1; end
                    FUNCT3_LHU: begin mem_size = MEM_HALF; load_unsigned = 1'b1; end
                    default: illegal_main = 1'b1;
                endcase
            end

            OPCODE_STORE : begin
                alu_sel_b = 1'b1;
                mem_write = 1'b1;
                wb_sel    = WB_MEM;
                imm_sel   = IMM_S;
                alu_op    = ALU_OP_ADD;
                case (funct3)
                    FUNCT3_SB: mem_size = MEM_BYTE;
                    FUNCT3_SH: mem_size = MEM_HALF;
                    FUNCT3_SW: mem_size = MEM_WORD;
                    default: illegal_main = 1'b1;
                endcase
            end

            OPCODE_JAL : begin
                reg_write = 1'b1;
                imm_sel   = IMM_J;
                wb_sel    = WB_PC4;
                alu_op    = ALU_OP_ADD;
                jump_and_link = 1'b1;
                pc_target_sel = PC_TARGET_PC_IMM;
                alu_src_a_sel = ALU_A_PC;
            end

             OPCODE_JALR : begin
                reg_write     = 1'b1;
                alu_sel_b     = 1'b1;
                imm_sel       = IMM_I;
                wb_sel        = WB_PC4;
                alu_op        = ALU_OP_ADD;
                jump_and_link = 1'b1;
                pc_target_sel = PC_TARGET_ALU;
                alu_src_a_sel = ALU_A_RS1;
                if(funct3 != FUNCT3_JALR)
                    illegal_main = 1'b1;
                else
                    illegal_main = 1'b0;
            end

            OPCODE_LUI : begin
                reg_write = 1'b1;
                alu_sel_b = 1'b1;
                imm_sel   = IMM_U;
                alu_op    = ALU_OP_ADD;
                alu_src_a_sel = ALU_A_ZERO;
            end

            OPCODE_AUIPC : begin
                reg_write = 1'b1;
                alu_sel_b = 1'b1;
                imm_sel   = IMM_U;
                alu_op    = ALU_OP_ADD;
                alu_src_a_sel = ALU_A_PC;
            end
            default: illegal_main = 1'b1;
        endcase
    end

    always_comb begin
        alu_ctrl   = ALU_ADD;
        illegal_alu = 1'b0;
        branch_on_zero = 1'b0;

        case (alu_op)
            ALU_OP_ADD : begin
                alu_ctrl = ALU_ADD;
            end

            ALU_OP_BRANCH : begin
                case (funct3)
                    FUNCT3_BEQ : begin alu_ctrl = ALU_SUB; branch_on_zero = 1'b1; end
                    FUNCT3_BNE : begin alu_ctrl = ALU_SUB; branch_on_zero = 1'b0; end
                    FUNCT3_BLT : begin alu_ctrl = ALU_SLT; branch_on_zero = 1'b0; end
                    FUNCT3_BGE : begin alu_ctrl = ALU_SLT; branch_on_zero = 1'b1; end
                    FUNCT3_BLTU: begin alu_ctrl = ALU_SLTU; branch_on_zero = 1'b0; end
                    FUNCT3_BGEU: begin alu_ctrl = ALU_SLTU; branch_on_zero = 1'b1; end
                    default    : illegal_alu = 1'b1;
                endcase
            end

            ALU_OP_RTYPE : begin
                case ({funct7, funct3})
                    {FUNCT7_ADD,  FUNCT3_ADD_SUB} : alu_ctrl = ALU_ADD;
                    {FUNCT7_SUB,  FUNCT3_ADD_SUB} : alu_ctrl = ALU_SUB;
                    {FUNCT7_AND,  FUNCT3_AND}     : alu_ctrl = ALU_AND;
                    {FUNCT7_OR,   FUNCT3_OR}      : alu_ctrl = ALU_OR;
                    {FUNCT7_XOR,  FUNCT3_XOR}     : alu_ctrl = ALU_XOR;
                    {FUNCT7_SLL,  FUNCT3_SLL}     : alu_ctrl = ALU_SLL;
                    {FUNCT7_SRL,  FUNCT3_SRL}     : alu_ctrl = ALU_SRL;
                    {FUNCT7_SRA,  FUNCT3_SRA}     : alu_ctrl = ALU_SRA;
                    {FUNCT7_SLT,  FUNCT3_SLT}     : alu_ctrl = ALU_SLT;
                    {FUNCT7_SLTU, FUNCT3_SLTU}    : alu_ctrl = ALU_SLTU;
                    default: illegal_alu = 1'b1;
                endcase
            end

            ALU_OP_ITYPE : begin
                case (funct3)
                    FUNCT3_ADDI  : alu_ctrl = ALU_ADD;
                    FUNCT3_SLTI  : alu_ctrl = ALU_SLT;
                    FUNCT3_SLTIU : alu_ctrl = ALU_SLTU;
                    FUNCT3_XORI  : alu_ctrl = ALU_XOR;
                    FUNCT3_ORI   : alu_ctrl = ALU_OR;
                    FUNCT3_ANDI  : alu_ctrl = ALU_AND;

                    FUNCT3_SLLI : begin
                        if (funct7 == FUNCT7_SLLI)
                            alu_ctrl = ALU_SLL;
                        else
                            illegal_alu = 1'b1;
                    end

                    FUNCT3_SRLI : begin
                        case (funct7)
                            FUNCT7_SRLI : alu_ctrl = ALU_SRL;
                            FUNCT7_SRAI : alu_ctrl = ALU_SRA;
                            default     : illegal_alu = 1'b1;
                        endcase
                    end

                /*    FUNCT3_SYSTEM : begin
                        case (funct7)
                            FUNCT7_ECALL : begin alu_ctrl = ALU_ADD; illegal_alu = 1'b0; end
                            FUNCT7_EBREAK: begin alu_ctrl = ALU_ADD; illegal_alu = 1'b0; end
                            default      : illegal_alu = 1'b1;
                        endcase
                    end
                    default: illegal_alu = 1'b1;
                */
                endcase
            end

            default: illegal_alu = 1'b1;
        endcase
    end

    assign illegal_instr = illegal_alu | illegal_main;
endmodule
