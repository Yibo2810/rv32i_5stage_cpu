`timescale 1ns/1ps

module if_stage
import pipeline_pkg::*;(
  input logic clk,
  input logic rst,
  input logic ex_redirect_taken,
  input logic [31:0] ex_redirect_pc,
  input logic ifid_take,
  input logic arbitration_redirect,

  output logic        imem_req_valid, // core says: I am ready
  output logic [31:0] imem_req_addr,
  input  logic        imem_req_ready, // momory says: I am ready

  output logic        imem_rsp_ready, // core
  input  logic        imem_rsp_valid, // memory
  input  logic [31:0] imem_rsp_rdata,

  output ifid_t   ifid_d
);
  logic [31:0] pc_current;
  logic [31:0] pc_next;
  fetch_state_t fetch_d, fetch_q;
  logic imem_req_fire;
  logic imem_rsp_fire;
  assign imem_req_fire = imem_req_ready && imem_req_valid;
  assign imem_rsp_fire = imem_rsp_ready && imem_rsp_valid;
  assign imem_rsp_ready = !fetch_q.buf_valid || fetch_q.killed || ex_redirect_taken || ifid_take;
  assign imem_req_valid = !fetch_q.pending || imem_rsp_fire;
  always_ff @(posedge clk) begin
    if (rst) begin
      fetch_q <= '0;
    end else begin
    fetch_q <= fetch_d;
    end
  end

  always_comb begin
    fetch_d = fetch_q;
    if (fetch_q.buf_valid && ifid_take) fetch_d.buf_valid = 1'b0;
    if (imem_rsp_fire && !fetch_q.killed && !ex_redirect_taken) begin
      fetch_d.buf_valid = 1'b1;
      fetch_d.buf_pc = fetch_q.pending_pc;
      fetch_d.buf_instr = imem_rsp_rdata;
    end
    if (ex_redirect_taken) begin
      fetch_d.buf_valid = 1'b0;
      if (fetch_q.pending) fetch_d.killed = 1'b1;
    end
    if (imem_rsp_fire) begin
      fetch_d.pending = 1'b0;
      fetch_d.killed = 1'b0;
    end
    if (imem_req_fire) begin
      fetch_d.pending_pc = imem_req_addr;
      fetch_d.pending = 1'b1;
      fetch_d.killed = 1'b0;
    end
  end 

  assign imem_req_addr =  arbitration_redirect ? ex_redirect_pc : pc_current;

  always_comb begin
    pc_next = pc_current;
    if (imem_req_fire) pc_next = imem_req_addr + 32'd4;
    else if (ex_redirect_taken) pc_next = ex_redirect_pc;
  end

  pc u_pc (
    .clk(clk),
    .rst(rst),
    .pc_next(pc_next),
    .pc(pc_current)
  );

  always_comb begin
    ifid_d = '0;

    ifid_d.valid     = fetch_q.buf_valid;
    ifid_d.pc        = fetch_q.buf_pc;
    ifid_d.pc_plus_4 = fetch_q.buf_pc + 32'd4;
    ifid_d.instr     = fetch_q.buf_instr;
  end
endmodule
`default_nettype wire
