`timescale 1ns/1ps
`default_nettype none

module id_stage
import pipeline_pkg::*;
import single_pkg::*;(
  input logic clk,
  input logic rst,

  input logic        wb_w_en,
  input logic [4:0]  wb_rd_addr,
  input logic [31:0] wb_rd_data,

  output logic [4:0] id_rs1_addr,
  output logic [4:0] id_rs2_addr,
  output logic       id_uses_rs1,
  output logic       id_uses_rs2,

  input ifid_t   ifid_q,
  output idex_t  idex_d
);
  logic [31:0] instr;

  logic [31:0] rf_rs1_data;
  logic [31:0] rf_rs2_data;
  logic [31:0] id_rs1_data;
  logic [31:0] id_rs2_data;

  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [4:0]  rd_addr;

  logic [31:0] imm;
  imm_sel_e    imm_sel;
  idex_ctrl_t  ctrl_final;
  idex_ctrl_t  ctrl;
  exception_t decode_exc;
  
  logic       ctrl_uses_rs1;
  logic       ctrl_uses_rs2;

  assign instr    = ifid_q.instr;
  assign rs1_addr = instr[19:15];
  assign rs2_addr = instr[24:20];
  assign rd_addr  = instr[11:7]; 
  // ID bypass
  assign id_rs1_data = (wb_w_en && wb_rd_addr != 5'd0 && wb_rd_addr == rs1_addr) ? wb_rd_data : rf_rs1_data;
  assign id_rs2_data = (wb_w_en && wb_rd_addr != 5'd0 && wb_rd_addr == rs2_addr) ? wb_rd_data : rf_rs2_data;
  always_comb begin
    ctrl_final = ctrl;
    ctrl_final.reg_write = ctrl.reg_write && (rd_addr != 5'd0) && !decode_exc.valid; //some synthesis tools don't support drive multiple drivers to a packed struct...
  end
  //ctrl
  assign id_rs1_addr = rs1_addr;
  assign id_rs2_addr = rs2_addr;
  assign id_uses_rs1 = ctrl_uses_rs1;
  assign id_uses_rs2 = ctrl_uses_rs2;

  always_comb begin
    idex_d = '0;

    if (ifid_q.valid) begin
      idex_d.valid     = 1'b1;
      idex_d.pc        = ifid_q.pc;
      idex_d.ctrl      = ctrl_final;
      idex_d.pc_plus_4 = ifid_q.pc_plus_4;
      idex_d.instr     = ifid_q.instr;

      idex_d.rs1_data = id_rs1_data;
      idex_d.rs2_data = id_rs2_data;
      idex_d.rs1_addr = rs1_addr;
      idex_d.rs2_addr = rs2_addr;
      idex_d.rd_addr  = rd_addr;
      idex_d.imm      = imm;
      idex_d.exc      = decode_exc;
    end
  end

  control_unit u_control_unit (
    .instr          (instr),
    .mem_write      (ctrl.mem_write),
    .mem_read       (ctrl.mem_read),
    .reg_write      (ctrl.reg_write),
    .alu_sel_b      (ctrl.alu_sel_b),
    .wb_sel         (ctrl.wb_sel),
    .branch         (ctrl.branch),
    .alu_ctrl       (ctrl.alu_ctrl),
    .imm_sel        (imm_sel),
    .branch_on_zero (ctrl.branch_on_zero),
    .mem_size       (ctrl.mem_size),
    .load_unsigned  (ctrl.load_unsigned),
    .jump_and_link  (ctrl.jump_and_link),
    .alu_src_a_sel  (ctrl.alu_src_a_sel),
    .pc_target_sel  (ctrl.pc_target_sel),
    .ctrl_uses_rs1  (ctrl_uses_rs1),
    .ctrl_uses_rs2  (ctrl_uses_rs2),
    .decode_exc     (decode_exc)
  );

  imm_gen u_imm_gen (
    .instr(instr),
    .imm_sel(imm_sel),
    .imm(imm)
  );

  regfile u_regfile (
    .clk       (clk),
    .rst       (rst),
    .w_en      (wb_w_en),
    .rs1_addr  (rs1_addr),
    .rs2_addr  (rs2_addr),
    .rd_addr   (wb_rd_addr),
    .rd_data   (wb_rd_data),
    .rs1_data  (rf_rs1_data),
    .rs2_data  (rf_rs2_data)
  );
endmodule
`default_nettype wire
