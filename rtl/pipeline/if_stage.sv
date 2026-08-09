`timescale 1ns/1ps

import pipeline_pkg::*;

module if_stage(
  input logic clk,
  input logic rst,

  input logic [31:0] imem_rdata,
  output logic [31:0] imem_addr,

  output ifid_t   ifid_d
);
  logic [31:0] pc_current;
  logic [31:0] pc_next;
  logic [31:0] pc_plus_4;

  assign pc_plus_4 = pc_current + 32'd4;
  assign pc_next   = pc_stall ? pc_current : redirect_valid ? redirect_pc : pc_plus_4;
  assign imem_addr = pc_current;

  pc u_pc (
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .pc(pc_current)
  );

  always_comb begin
    ifid_d = '0;

    ifid_d.valid     = 1'b1;
    ifid_d.pc        = pc_current;
    ifid_d.pc_plus_4 = pc_plus_4;
    ifid_d.instr     = imem_rdata;
  end
endmodule

