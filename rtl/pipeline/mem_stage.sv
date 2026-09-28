`timescale 1ns/1ps
`default_nettype none

module mem_stage 
import single_pkg::*;
import pipeline_pkg::*;(
  input exmem_t      exmem_q,
  input logic [31:0] dmem_rsp_rdata,
  input logic        dmem_rsp_valid,
  input logic        dmem_req_ready,
  
  input logic        clk,
  input logic        rst,

  output logic       dmem_req_write,
  output logic       dmem_req_valid,
  output logic       dmem_rsp_ready,
  output logic [31:0] dmem_req_addr,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0] dmem_req_wstrb,

  output logic       mem_stall,
  input logic       wb_exc_pending,

  output memwb_t memwb_d
);

  logic [31:0] lsu_wdata;
  logic [3:0]  lsu_wstrb;
  logic [31:0] load_data;
  logic        mem_op;
  logic        mem_active;
  logic        mem_misaligned;
  logic        mem_fault;
  logic        mem_go;
  exception_t  mem_exc;
  logic        req_sent, req_fire, rsp_fire, mem_done;

  assign mem_op     = exmem_q.ctrl_m.mem_read || exmem_q.ctrl_m.mem_write;
  assign mem_active = exmem_q.valid && !exmem_q.exc.valid && mem_op;
  assign mem_fault  = mem_active && mem_misaligned;
  assign mem_go     = mem_active && !mem_misaligned && !wb_exc_pending;

  assign dmem_req_valid = mem_go && !req_sent;
  assign dmem_req_addr  = exmem_q.alu_result;
  assign dmem_req_write = mem_go && exmem_q.ctrl_m.mem_write;
  assign dmem_req_wdata = dmem_req_write ? lsu_wdata : 32'b0;
  assign dmem_req_wstrb = dmem_req_write ? lsu_wstrb : 4'b0000;
  assign dmem_rsp_ready = 1'b1;

  assign req_fire = dmem_req_valid && dmem_req_ready;
  assign rsp_fire = dmem_rsp_valid && dmem_rsp_ready;
  assign mem_done = req_sent && rsp_fire;
  assign mem_stall = mem_go && !mem_done;

  always_ff @( posedge clk ) begin
    if (rst)           req_sent <= 1'b0;
    else if (req_fire) req_sent <= 1'b1;
    else if (mem_done) req_sent <= 1'b0;
  end
  always_comb begin
    memwb_d = '0;

    if (exmem_q.valid) begin
      memwb_d.valid      = 1'b1;
      memwb_d.pc         = exmem_q.pc;
      memwb_d.instr      = exmem_q.instr;
      memwb_d.next_pc    = exmem_q.next_pc;
      memwb_d.alu_result = exmem_q.alu_result;
      memwb_d.load_data  = load_data;
      memwb_d.pc_plus_4   = exmem_q.pc_plus_4;
      memwb_d.rd_addr    = exmem_q.rd_addr;

      memwb_d.ctrl_wb.reg_write     = exmem_q.ctrl_m.reg_write && !mem_exc.valid;
      memwb_d.ctrl_wb.wb_sel        = exmem_q.ctrl_m.wb_sel;
      memwb_d.exc = mem_exc;
    end
  end

  always_comb begin
    mem_exc = exmem_q.exc;
    if (mem_fault) begin
      mem_exc.valid = 1'b1;
      mem_exc.cause = exmem_q.ctrl_m.mem_write ? EXC_STORE_ADDR_MISALIGNED : EXC_LOAD_ADDR_MISALIGNED;
    end
  end

  load_store_unit u_lsu (
    .addr_offset(exmem_q.alu_result[1:0]),
    .store_data(exmem_q.store_data),
    .mem_size(exmem_q.ctrl_m.mem_size),
    .load_unsigned(exmem_q.ctrl_m.load_unsigned),
    .mem_wdata(lsu_wdata),
    .mem_wstrb(lsu_wstrb),
    .mem_rdata(dmem_rsp_rdata),
    .load_data(load_data),
    .misaligned(mem_misaligned)
  );
endmodule
`default_nettype wire
