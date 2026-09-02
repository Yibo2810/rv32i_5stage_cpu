`timescale 1ns/1ps

module wb_stage 
import single_pkg::*;
import pipeline_pkg::*;(
  input memwb_t memwb_q,

  output logic       wb_w_en,
  output logic [4:0] wb_rd_addr,
  output logic [31:0] wb_rd_data,

  output logic       sys_ecall,
  output logic       sys_ebreak
);
  logic wb_side_effect_ok;

  assign wb_side_effect_ok = memwb_q.valid && !memwb_q.ctrl_wb.illegal_instr && !memwb_q.ctrl_wb.mem_fault;

  assign wb_w_en    = wb_side_effect_ok && memwb_q.ctrl_wb.reg_write && (memwb_q.rd_addr != 5'b0);
  assign wb_rd_addr = memwb_q.rd_addr;
  assign sys_ecall  = wb_side_effect_ok && memwb_q.ctrl_wb.sys_ecall;
  assign sys_ebreak = wb_side_effect_ok && memwb_q.ctrl_wb.sys_ebreak;

  always_comb begin
    case (memwb_q.ctrl_wb.wb_sel)
      WB_ALU: wb_rd_data = memwb_q.alu_result;
      WB_MEM: wb_rd_data = memwb_q.load_data;
      WB_PC4: wb_rd_data = memwb_q.pc_plus_4;
      default: wb_rd_data = 32'b0;
    endcase
  end
endmodule

