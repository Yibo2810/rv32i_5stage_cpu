`timescale 1ns/1ps

module mem_stage 
import single_pkg::*;
import pipeline_pkg::*;(
  input exmem_t      exmem_q,
  input logic [31:0] dmem_rdata,

  output logic       dmem_read,
  output logic       dmem_write,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0] dmem_wstrb,

  output memwb_t memwb_d
);

  logic [31:0] lsu_wdata;
  logic [3:0]  lsu_wstrb;
  logic [31:0] load_data;
  logic        mem_misaligned;
  logic        mem_req;
  logic        mem_fault;
  logic        mem_side_effect_ok;

  assign mem_req = exmem_q.valid && !exmem_q.ctrl_m.illegal_instr && (exmem_q.ctrl_m.mem_read || exmem_q.ctrl_m.mem_write);
  assign mem_fault = mem_req && mem_misaligned;
  assign mem_side_effect_ok = mem_req && !mem_fault;

  assign dmem_addr = exmem_q.alu_result;
  assign dmem_read = exmem_q.ctrl_m.mem_read && mem_side_effect_ok;
  assign dmem_write = exmem_q.ctrl_m.mem_write && mem_side_effect_ok;
  assign dmem_wdata = dmem_write ? lsu_wdata : 32'b0;
  assign dmem_wstrb = dmem_write ? lsu_wstrb : 4'b0000;

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

      memwb_d.ctrl_wb.reg_write     = exmem_q.ctrl_m.reg_write && !mem_fault;
      memwb_d.ctrl_wb.wb_sel        = exmem_q.ctrl_m.wb_sel;
      memwb_d.ctrl_wb.illegal_instr = exmem_q.ctrl_m.illegal_instr;
      memwb_d.ctrl_wb.mem_fault     = mem_fault;
      memwb_d.ctrl_wb.sys_ecall     = exmem_q.ctrl_m.sys_ecall;
      memwb_d.ctrl_wb.sys_ebreak    = exmem_q.ctrl_m.sys_ebreak;
    end
  end

  load_store_unit u_lsu (
    .addr_offset(exmem_q.alu_result[1:0]),
    .store_data(exmem_q.store_data),
    .mem_size(exmem_q.ctrl_m.mem_size),
    .load_unsigned(exmem_q.ctrl_m.load_unsigned),
    .mem_wdata(lsu_wdata),
    .mem_wstrb(lsu_wstrb),
    .mem_rdata(dmem_rdata),
    .load_data(load_data),
    .misaligned(mem_misaligned)
  );
endmodule

