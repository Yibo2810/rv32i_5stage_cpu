`timescale 1ns/1ps
`default_nettype none

module wb_stage 
import single_pkg::*;
import pipeline_pkg::*;(
  input memwb_t memwb_q,
  input logic  mem_stall,

  output logic       wb_w_en,
  output logic [4:0] wb_rd_addr,
  output logic [31:0] wb_rd_data,

  output logic        trap_valid,
  output exc_cause_e  trap_cause,
  output logic [31:0] trap_pc,
  output logic        wb_trap
);
  logic wb_retire;

  assign wb_retire = memwb_q.valid && !mem_stall;
  assign wb_trap = wb_retire && memwb_q.exc.valid;

  assign wb_w_en    = wb_retire && !memwb_q.exc.valid && memwb_q.ctrl_wb.reg_write && (memwb_q.rd_addr != 5'b0);
  assign wb_rd_addr = memwb_q.rd_addr;

  assign trap_valid = wb_trap;
  assign trap_pc = memwb_q.pc;
  assign trap_cause = memwb_q.exc.cause;

  always_comb begin
    case (memwb_q.ctrl_wb.wb_sel)
      WB_ALU: wb_rd_data = memwb_q.alu_result;
      WB_MEM: wb_rd_data = memwb_q.load_data;
      WB_PC4: wb_rd_data = memwb_q.pc_plus_4;
      default: wb_rd_data = 32'b0;
    endcase
  end
endmodule
`default_nettype wire
