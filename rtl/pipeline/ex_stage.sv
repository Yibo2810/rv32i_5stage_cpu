`timescale 1ns/1ps

module ex_stage
import single_pkg::*;
import pipeline_pkg::*;(
  input  idex_t       idex_q,

  input  logic [31:0] exmem_fwd_data,
  input  logic [31:0] memwb_fwd_data,
  input  fwd_sel_e  fwd_a_sel,
  input  fwd_sel_e  fwd_b_sel,

  output exmem_t      exmem_d,
  output logic        ex_redirect_taken,
  output logic [31:0] ex_redirect_pc
);

  logic [31:0] ex_rs1_fwd;
  logic [31:0] ex_rs2_fwd;

  logic [31:0] alu_src_a;
  logic [31:0] alu_src_b;
  logic [31:0] alu_result;
  logic        alu_zero;

  logic        branch_taken;
  logic        ex_side_effect_ok;
  logic [31:0] ex_pc_next;

  always_comb begin
    case (fwd_a_sel)
      FWD_EXMEM: ex_rs1_fwd = exmem_fwd_data;
      FWD_MEMWB: ex_rs1_fwd = memwb_fwd_data;
      default:   ex_rs1_fwd = idex_q.rs1_data;
    endcase
  end

  always_comb begin
    case (fwd_b_sel)
      FWD_EXMEM: ex_rs2_fwd = exmem_fwd_data;
      FWD_MEMWB: ex_rs2_fwd = memwb_fwd_data;
      default:   ex_rs2_fwd = idex_q.rs2_data;
    endcase
  end

  always_comb begin
    case (idex_q.ctrl.alu_src_a_sel)
      ALU_A_RS1: alu_src_a = ex_rs1_fwd;
      ALU_A_PC : alu_src_a = idex_q.pc;
      ALU_A_ZERO: alu_src_a = 32'b0;
      default: alu_src_a = 32'b0;
    endcase
  end

  assign alu_src_b = idex_q.ctrl.alu_sel_b ? idex_q.imm : ex_rs2_fwd;
  assign branch_taken = idex_q.ctrl.branch && (alu_zero == idex_q.ctrl.branch_on_zero);
  assign ex_side_effect_ok = idex_q.valid && !idex_q.ctrl.illegal_instr;
  assign ex_redirect_taken = ex_side_effect_ok && (branch_taken || idex_q.ctrl.jump_and_link);
  assign ex_redirect_pc = (idex_q.ctrl.pc_target_sel == PC_TARGET_ALU) ? {alu_result[31:1], 1'b0} : (idex_q.pc + idex_q.imm);
  assign ex_pc_next = ex_redirect_taken ? ex_redirect_pc : idex_q.pc_plus_4;

  always_comb begin
    exmem_d = '0;

    if (idex_q.valid) begin
      exmem_d.valid = 1'b1;
      exmem_d.pc = idex_q.pc;
      exmem_d.pc_plus_4 = idex_q.pc_plus_4;
      exmem_d.next_pc = ex_pc_next;
      exmem_d.instr = idex_q.instr;

      exmem_d.alu_result = alu_result;
      exmem_d.store_data = ex_rs2_fwd;  //not alu_src_b
      exmem_d.rd_addr = idex_q.rd_addr;

      exmem_d.ctrl_m.mem_read = idex_q.ctrl.mem_read;
      exmem_d.ctrl_m.mem_write = idex_q.ctrl.mem_write;
      exmem_d.ctrl_m.mem_size = idex_q.ctrl.mem_size;
      exmem_d.ctrl_m.load_unsigned = idex_q.ctrl.load_unsigned;
      exmem_d.ctrl_m.reg_write = idex_q.ctrl.reg_write;
      exmem_d.ctrl_m.wb_sel = idex_q.ctrl.wb_sel;
      exmem_d.ctrl_m.illegal_instr = idex_q.ctrl.illegal_instr;
      exmem_d.ctrl_m.sys_ecall = idex_q.ctrl.sys_ecall;
      exmem_d.ctrl_m.sys_ebreak = idex_q.ctrl.sys_ebreak;
    end
  end

  alu u_alu (
    .src_a(alu_src_a),
    .src_b(alu_src_b),
    .zero(alu_zero),
    .result(alu_result),
    .alu_ctrl(idex_q.ctrl.alu_ctrl)
  );
endmodule

