`timescale 1ns/1ps

import single_pkg::*;
import pipeline_pkg::*;

module core_5stage (
  input  logic        clk,
  input  logic        rst,
  input  logic [31:0] imem_rdata,
  output logic [31:0] imem_addr,

  output logic        dmem_read,
  output logic        dmem_write,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wstrb,
  input  logic [31:0] dmem_rdata,

  output logic        sys_ecall,
  output logic        sys_ebreak
);
  logic       wb_w_en;
  logic [4:0] wb_rd_addr;
  logic [31:0] wb_rd_data;
  
  ifid_t  ifid_q,  ifid_d;
  idex_t  idex_q,  idex_d;
  exmem_t exmem_q, exmem_d;
  memwb_t memwb_q, memwb_d;

  pipeline_regs u_pipeline_regs (
    .clk     (clk),
    .rst     (rst),
    .ifid_d  (ifid_d),
    .idex_d  (idex_d),
    .exmem_d (exmem_d),
    .memwb_d (memwb_d),
    .ifid_q  (ifid_q),
    .idex_q  (idex_q),
    .exmem_q (exmem_q),
    .memwb_q (memwb_q)
  );

  if_stage u_if_stage(
    .clk(clk),
    .rst(rst),
    .imem_rdata(imem_rdata),
    .imem_addr(imem_addr),
    .ifid_d(ifid_d)
  );

  id_stage u_id_stage (
    .clk(clk),
    .rst(rst),
    .ifid_q(ifid_q),
    .wb_w_en(wb_w_en),
    .wb_rd_addr(wb_rd_addr),
    .wb_rd_data(wb_rd_data),
    .idex_d(idex_d)
  );

  logic ex_redirect_taken;
  logic [31:0] ex_redirect_pc;

  ex_stage u_ex_stage (
    .idex_q(idex_q),
    .exmem_d(exmem_d),
    .ex_redirect_taken(ex_redirect_taken),
    .ex_redirect_pc(ex_redirect_pc)
  );

  mem_stage u_mem_stage (
    .exmem_q(exmem_q),
    .dmem_rdata(dmem_rdata),
    .dmem_read(dmem_read),
    .dmem_write(dmem_write),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wstrb(dmem_wstrb),
    .memwb_d(memwb_d)
  );

  wb_stage u_wb_stage (
    .memwb_q(memwb_q),
    .wb_w_en(wb_w_en),
    .wb_rd_addr(wb_rd_addr),
    .wb_rd_data(wb_rd_data),
    .sys_ecall(sys_ecall),
    .sys_ebreak(sys_ebreak)
  );
endmodule