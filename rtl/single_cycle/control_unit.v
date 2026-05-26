`timescale 1ns/1ps
`include "rv32i_defs.vh"

module control_unit(
    input [31:0] instr,
    output reg       mem_write,
    output reg       mem_read,
    output reg       reg_write,
    output reg       alu_src,
    output reg       wb_sel,
    output reg       branch,
    output reg [3:0] alu_ctrl,
    output reg [2:0] imm_sel,
    output           illegal_instr
);
    reg  [1:0] alu_op;
    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];
    wire [2:0] funct3 = instr[14:12];

    reg illegal_main;
    reg illegal_alu;

    localparam ALU_OP_ADD    = 2'b00;  // addi, lw, sw
    localparam ALU_OP_BRANCH = 2'b01;  // beq
    localparam ALU_OP_RTYPE  = 2'b10;  // add, sub, later and/or/xor
    localparam ALU_OP_ITYPE  = 2'b11;  // andi/ori/slti/sltiu


    always @(*) begin
        mem_write  = 1'b0;
        mem_read   = 1'b0;
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        wb_sel     = 1'b0;
        branch     = 1'b0;
        imm_sel    = `RV32I_IMM_I;
        alu_op     = ALU_OP_ADD;
        illegal_main = 1'b0;
        case (opcode)

            `RV32I_OPCODE_R_TYPE : begin
                reg_write = 1'b1;
                imm_sel   = `RV32I_IMM_NONE;
                alu_op    = ALU_OP_RTYPE;
            end

            `RV32I_OPCODE_I_TYPE : begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_sel   = `RV32I_IMM_I;
                alu_op    = ALU_OP_ITYPE;
            end

            `RV32I_OPCODE_BRANCH : begin
                branch  = 1'b1;
                imm_sel = `RV32I_IMM_B;
                alu_op  = ALU_OP_BRANCH;
            end

            `RV32I_OPCODE_LOAD : begin
                reg_write = 1'b1;
                mem_read  = 1'b1;
                alu_src   = 1'b1;
                wb_sel    = `RV32I_WB_MEM;
                imm_sel   = `RV32I_IMM_I;
                alu_op    = ALU_OP_ADD;
            end

            `RV32I_OPCODE_STORE : begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                wb_sel    = `RV32I_WB_MEM;
                imm_sel   = `RV32I_IMM_S;
                alu_op    = ALU_OP_ADD;
            end
            default: illegal_main = 1'b1;
        endcase
    end

    always @(*) begin
        alu_ctrl = `RV32I_ALU_ADD;
        illegal_alu = 1'b0;

        case (alu_op)

            ALU_OP_ADD : begin
                alu_ctrl = `RV32I_ALU_ADD;
            end

            ALU_OP_BRANCH : begin
                alu_ctrl = `RV32I_ALU_SUB;
            end

            ALU_OP_RTYPE : begin
                case ({funct7,funct3})
                    {`RV32I_FUNCT7_ADD, `RV32I_FUNCT3_ADD_SUB} : alu_ctrl = `RV32I_ALU_ADD;
                    {`RV32I_FUNCT7_SUB, `RV32I_FUNCT3_ADD_SUB} : alu_ctrl = `RV32I_ALU_SUB;
                    {`RV32I_FUNCT7_AND, `RV32I_FUNCT3_AND}     : alu_ctrl = `RV32I_ALU_AND;
                    {`RV32I_FUNCT7_OR,  `RV32I_FUNCT3_OR}      : alu_ctrl = `RV32I_ALU_OR;
                    {`RV32I_FUNCT7_XOR, `RV32I_FUNCT3_XOR}     : alu_ctrl = `RV32I_ALU_XOR;
                    {`RV32I_FUNCT7_SLL, `RV32I_FUNCT3_SLL}     : alu_ctrl = `RV32I_ALU_SLL;
                    {`RV32I_FUNCT7_SRL, `RV32I_FUNCT3_SRL}     : alu_ctrl = `RV32I_ALU_SRL;
                    {`RV32I_FUNCT7_SRA, `RV32I_FUNCT3_SRA}     : alu_ctrl = `RV32I_ALU_SRA;
                    {`RV32I_FUNCT7_SLT, `RV32I_FUNCT3_SLT}     : alu_ctrl = `RV32I_ALU_SLT;
                    {`RV32I_FUNCT7_SLTU,`RV32I_FUNCT3_SLTU}    : alu_ctrl = `RV32I_ALU_SLTU;
                    default: illegal_alu = 1'b1;
                endcase
            end

                ALU_OP_ITYPE : begin
                case ({funct3})
                    `RV32I_FUNCT3_ADDI  : alu_ctrl = `RV32I_ALU_ADD;
                    `RV32I_FUNCT3_SLTI  : alu_ctrl = `RV32I_ALU_SLT;
                    `RV32I_FUNCT3_SLTIU : alu_ctrl = `RV32I_ALU_SLTU;
                    `RV32I_FUNCT3_XORI  : alu_ctrl = `RV32I_ALU_XOR;
                    `RV32I_FUNCT3_ORI   : alu_ctrl = `RV32I_ALU_OR;
                    `RV32I_FUNCT3_ANDI  : alu_ctrl = `RV32I_ALU_AND;

                    `RV32I_FUNCT3_SLLI : begin
                        if(funct7 == 7'b0000000)
                            alu_ctrl = `RV32I_ALU_SLL;
                        else
                            illegal_alu = 1'b1;
                    end

                    `RV32I_FUNCT3_SRLI : begin
                        case (funct7)
                            7'b0000000 : alu_ctrl = `RV32I_ALU_SRL;
                            7'b0100000 : alu_ctrl = `RV32I_ALU_SRA;
                            default : illegal_alu = 1'b1;
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

