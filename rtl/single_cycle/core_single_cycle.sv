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
    input logic [31:0] dmem_rdata
);

    // 1. logics
    logic        branch_taken;
    logic [31:0] pc_next;
    logic [31:0] pc_current;
    logic [31:0] pc_plus_4;
    logic [31:0] branch_target;

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

    logic mem_read;
    logic mem_write;
    logic reg_write;
    logic alu_src;
    wb_sel_e wb_sel;
    logic branch;
    alu_ctrl_e alu_ctrl;
    imm_sel_e imm_sel;
    logic illegal_instr;

    // 2. assign statements
    assign instr     = imem_rdata;
    assign imem_addr = pc_current;
    assign pc_plus_4 = pc_current + 32'd4;
    assign pc_next   = branch_taken ? branch_target : pc_plus_4;

    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign rd_addr  = instr[11:7];

    assign alu_src_a = rs1_data;
    assign alu_src_b = alu_src ? imm : rs2_data;

    assign dmem_addr  = alu_result;
    assign dmem_read  = mem_read;
    assign dmem_write = mem_write;
    assign dmem_wdata = rs2_data;
    assign rd_data = wb_sel ? dmem_rdata : alu_result;

    assign branch_target = pc_current + imm;
    assign branch_taken = alu_zero & branch;
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
        .w_en(reg_write),
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
        .alu_src(alu_src),
        .wb_sel(wb_sel),
        .branch(branch),
        .alu_ctrl(alu_ctrl),
        .imm_sel(imm_sel),
        .illegal_instr(illegal_instr)
    );
endmodule
