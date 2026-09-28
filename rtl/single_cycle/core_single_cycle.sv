`timescale 1ns/1ps

import single_pkg::*;

module core_single_cycle(
    input logic rst,
    input logic clk,

    input logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,

    output logic dmem_read,
    output logic dmem_write,

    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
    input logic [31:0] dmem_rdata,
    output logic sys_ecall,
    output logic sys_ebreak
);

    // 1. logics
    logic        branch_taken;
    logic [31:0] pc_next;
    logic [31:0] pc_current;
    logic [31:0] pc_plus_4;

    logic [31:0] alu_src_a;
    logic [31:0] alu_src_b;
    logic [31:0] alu_result;
    logic        alu_zero;

    logic [31:0] instr;
    logic [31:0] imm;

    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;

    logic [31:0] rd_data;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    mem_size_e   mem_size;
    logic        load_unsigned;
    logic [31:0] load_data;
    logic        mem_misaligned;

    logic           mem_read;
    logic           mem_write;
    logic           mem_fault;
    logic           reg_write;
    logic           regfile_w_en;
    logic           alu_sel_b;
    wb_sel_e        wb_sel;
    alu_src_a_sel_e alu_src_a_sel;
    logic           branch;
    alu_ctrl_e      alu_ctrl;
    imm_sel_e       imm_sel;
    logic           illegal_instr;
    pc_target_sel_e pc_target_sel;
    logic           jump_and_link;
    logic           side_effect_ok;
    logic           branch_on_zero;
    logic           ctrl_uses_rs1;
    logic           ctrl_uses_rs2;

    // 2. assign statements
    assign instr          = imem_rdata;
    assign imem_addr      = pc_current;

    assign rs1_addr      = instr[19:15];
    assign rs2_addr      = instr[24:20];
    assign rd_addr       = instr[11:7];
    assign alu_src_b     = alu_sel_b ? imm : rs2_data;
    assign dmem_addr     = alu_result;
    assign mem_fault     = (mem_write || mem_read) && mem_misaligned;
    assign side_effect_ok = !rst && !illegal_instr && !mem_fault;
    assign dmem_read     = mem_read && side_effect_ok;
    assign dmem_write    = mem_write && side_effect_ok;
    assign regfile_w_en  = reg_write && side_effect_ok;

    assign branch_taken = branch && (alu_zero == branch_on_zero);


    always_comb begin
        case (wb_sel)
            WB_ALU : rd_data = alu_result;
            WB_MEM : rd_data = load_data;
            WB_PC4 : rd_data = pc_plus_4;
            default: rd_data = 32'b0;
        endcase
    end

    always_comb begin
        case (alu_src_a_sel)
            ALU_A_RS1 : alu_src_a = rs1_data;
            ALU_A_PC  : alu_src_a = pc_current;
            ALU_A_ZERO: alu_src_a = 32'b0;
            default   : alu_src_a = 32'bx;
        endcase
    end

    // 3. module instances
    pc u_pc (
        .clk(clk),
        .rst(rst),
        .pc_next(pc_next),
        .pc(pc_current)
    );

    alu u_alu (
        .src_a(alu_src_a),
        .src_b(alu_src_b),
        .zero(alu_zero),
        .result(alu_result),
        .alu_ctrl(alu_ctrl)
    );

   regfile u_regfile (
        .clk(clk),
        .rst(rst),
        .w_en(regfile_w_en),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    imm_gen u_imm_gen (
        .instr(instr),
        .imm_sel(imm_sel),
        .imm(imm)
    );

    control_unit u_control_unit (
        .instr(instr),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .reg_write(reg_write),
        .alu_sel_b(alu_sel_b),
        .wb_sel(wb_sel),
        .branch(branch),
        .alu_ctrl(alu_ctrl),
        .imm_sel(imm_sel),
        .branch_on_zero(branch_on_zero),
        .mem_size(mem_size),
        .load_unsigned(load_unsigned),
        .illegal_instr(illegal_instr),
        .jump_and_link(jump_and_link),
        .pc_target_sel(pc_target_sel),
        .alu_src_a_sel(alu_src_a_sel),
        .sys_ecall(sys_ecall),
        .sys_ebreak(sys_ebreak),
        .ctrl_uses_rs1(ctrl_uses_rs1),
        .ctrl_uses_rs2(ctrl_uses_rs2)
    );

    load_store_unit u_lsu (
        .mem_size     (mem_size),
        .load_unsigned(load_unsigned),
        .addr_offset  (alu_result[1:0]),
        .store_data   (rs2_data),
        .mem_rdata    (dmem_rdata),
        .mem_wdata    (dmem_wdata),
        .mem_wstrb    (dmem_wstrb),
        .load_data    (load_data),
        .misaligned   (mem_misaligned)
    );

    pc_redirect_unit u_pc_redirect_unit (
        .pc_current(pc_current),
        .imm(imm),
        .alu_result(alu_result),
        .branch_taken(branch_taken),
        .jump_and_link(jump_and_link),
        .side_effect_ok(side_effect_ok),
        .pc_target_sel(pc_target_sel),
        .pc_next(pc_next),
        .pc_plus_4(pc_plus_4)
    );
endmodule
