`timescale 1ns/1ps

import single_pkg::*;

module control_unit(
    input  logic [31:0]     instr,
    output logic            mem_write,
    output logic            mem_read,
    output logic            reg_write,
    output logic            alu_src,
    output wb_sel_e         wb_sel,
    output logic            branch,
    output alu_ctrl_e       alu_ctrl,
    output imm_sel_e        imm_sel,
    output logic            illegal_instr
);
    typedef enum logic [1:0] {
        ALU_OP_ADD    = 2'b00,  // addi, lw, sw
        ALU_OP_BRANCH = 2'b01,  // beq
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
        alu_src      = 1'b0;
        wb_sel       = WB_ALU;
        branch       = 1'b0;
        imm_sel      = IMM_I;
        alu_op       = ALU_OP_ADD;
        illegal_main = 1'b0;

        case (opcode)
            OPCODE_R_TYPE : begin
                reg_write = 1'b1;
                imm_sel   = IMM_NONE;
                alu_op    = ALU_OP_RTYPE;
            end

            OPCODE_I_TYPE : begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_sel   = IMM_I;
                alu_op    = ALU_OP_ITYPE;
            end

            OPCODE_BRANCH : begin
                branch  = 1'b1;
                imm_sel = IMM_B;
                alu_op  = ALU_OP_BRANCH;
            end

            OPCODE_LOAD : begin
                reg_write = 1'b1;
                mem_read  = 1'b1;
                alu_src   = 1'b1;
                wb_sel    = WB_MEM;
                imm_sel   = IMM_I;
                alu_op    = ALU_OP_ADD;
            end

            OPCODE_STORE : begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                wb_sel    = WB_MEM;
                imm_sel   = IMM_S;
                alu_op    = ALU_OP_ADD;
            end

            default: illegal_main = 1'b1;
        endcase
    end

    always_comb begin
        alu_ctrl   = ALU_ADD;
        illegal_alu = 1'b0;

        case (alu_op)
            ALU_OP_ADD : begin
                alu_ctrl = ALU_ADD;
            end

            ALU_OP_BRANCH : begin
                alu_ctrl = ALU_SUB;
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
                            default           : illegal_alu = 1'b1;
                        endcase
                    end

                    default: illegal_alu = 1'b1;
                endcase
            end

            default: illegal_alu = 1'b1;
        endcase
    end

    assign illegal_instr = illegal_alu | illegal_main;
endmodule
