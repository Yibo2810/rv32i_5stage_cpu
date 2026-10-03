`timescale 1ns/1ps

module core_5stage 
import single_pkg::*;
import pipeline_pkg::*;(
  input  logic        clk,
  input  logic        rst,
  output logic        imem_req_valid, // core says: I am ready
  output logic [31:0] imem_req_addr,
  input  logic        imem_req_ready, // momory says: I am ready

  output logic        imem_rsp_ready, // core
  input  logic        imem_rsp_valid, // memory
  input  logic [31:0] imem_rsp_rdata,

  input  logic        dmem_req_ready, // memory says: I am ready to accept a request
  output logic        dmem_req_valid,
  output logic        dmem_req_write,
  output logic [31:0] dmem_req_addr,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0]  dmem_req_wstrb,

  input  logic [31:0] dmem_rsp_rdata,
  output logic        dmem_rsp_ready,  // core says: I am ready to accept a response
  input  logic        dmem_rsp_valid,  // memory says: I have a response for you

  output logic        trap_valid,
  output exc_cause_e  trap_cause,
  output logic[31:0]  trap_pc,
  output logic        halted
);
  logic       wb_w_en;
  logic [4:0] wb_rd_addr;
  logic [31:0] wb_rd_data;
  
  ifid_t  ifid_q,  ifid_d;
  idex_t  idex_q,  idex_d;
  exmem_t exmem_q, exmem_d;
  memwb_t memwb_q, memwb_d;

  logic ex_redirect_taken;
  logic [31:0] ex_redirect_pc;
  logic [4:0] id_rs1_addr;
  logic [4:0] id_rs2_addr;
  logic [31:0] exmem_fwd_data;
  logic [31:0] memwb_fwd_data;
  logic id_uses_rs1, id_uses_rs2;
  logic ifid_flush, ifid_en;
  logic idex_en,    idex_flush;
  logic exmem_en,   exmem_flush;
  logic memwb_en,   memwb_flush;
  logic mem_stall;
  logic wb_exc_pending;
  fwd_sel_e fwd_a_sel, fwd_b_sel;
  logic wb_trap;
  logic ifid_take;
  logic arbitration_redirect;

  assign arbitration_redirect = ex_redirect_taken && !mem_stall && !wb_trap && !halted;
  assign memwb_fwd_data = wb_rd_data;
  assign wb_exc_pending = memwb_q.valid && memwb_q.exc.valid;

  always_ff @( posedge clk ) begin
    if (rst) begin
      halted <= 1'b0;
    end else if (trap_valid) begin
      halted <= 1'b1;
    end
  end

  always_comb begin
    case (exmem_q.ctrl_m.wb_sel)
      WB_ALU: exmem_fwd_data = exmem_q.alu_result;
      WB_PC4: exmem_fwd_data = exmem_q.pc_plus_4;
      default: exmem_fwd_data = 32'b0; // WB_MEM is covered by load-use stall and memwb.(load data is not ready until the next cycle)
    endcase
  end

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
    .memwb_q (memwb_q),
    .ifid_en (ifid_en),
    .ifid_flush (ifid_flush),
    .idex_en(idex_en),
    .idex_flush (idex_flush),
    .memwb_en (memwb_en),
    .memwb_flush (memwb_flush),
    .exmem_en (exmem_en),
    .exmem_flush (exmem_flush)
  );

  if_stage u_if_stage(
    .clk(clk),
    .rst(rst),
    .imem_rsp_rdata(imem_rsp_rdata),
    .imem_req_addr(imem_req_addr),
    .imem_req_ready(imem_req_ready),
    .imem_req_valid(imem_req_valid),
    .imem_rsp_ready(imem_rsp_ready),
    .imem_rsp_valid(imem_rsp_valid),
    .ifid_d(ifid_d),
    .ex_redirect_taken(ex_redirect_taken),
    .ex_redirect_pc(ex_redirect_pc),
    .ifid_take(ifid_en && !ifid_flush),
    .arbitration_redirect(arbitration_redirect)
  );

  id_stage u_id_stage (
    .clk(clk),
    .rst(rst),
    .ifid_q(ifid_q),
    .wb_w_en(wb_w_en),
    .wb_rd_addr(wb_rd_addr),
    .wb_rd_data(wb_rd_data),
    .idex_d(idex_d),
    .id_rs1_addr(id_rs1_addr),
    .id_rs2_addr(id_rs2_addr),
    .id_uses_rs1(id_uses_rs1),
    .id_uses_rs2(id_uses_rs2)
  );

  ex_stage u_ex_stage (
    .idex_q(idex_q),
    .exmem_d(exmem_d),
    .ex_redirect_taken(ex_redirect_taken),
    .ex_redirect_pc(ex_redirect_pc),
    .fwd_a_sel(fwd_a_sel),
    .fwd_b_sel(fwd_b_sel),
    .exmem_fwd_data(exmem_fwd_data),
    .memwb_fwd_data(memwb_fwd_data)
  );

  mem_stage u_mem_stage (
    .exmem_q(exmem_q),
    .dmem_rsp_rdata(dmem_rsp_rdata),
    .dmem_req_ready(dmem_req_ready),
    .dmem_rsp_valid(dmem_rsp_valid),
    .dmem_rsp_ready(dmem_rsp_ready),
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_write(dmem_req_write),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_wstrb(dmem_req_wstrb),
    .memwb_d(memwb_d),
    .mem_stall(mem_stall),
    .wb_exc_pending(wb_exc_pending),
    .clk(clk),
    .rst(rst)
  );

  wb_stage u_wb_stage (
    .memwb_q(memwb_q),
    .wb_w_en(wb_w_en),
    .wb_rd_addr(wb_rd_addr),
    .wb_rd_data(wb_rd_data),
    .trap_cause(trap_cause),
    .trap_pc(trap_pc),
    .trap_valid(trap_valid),
    .mem_stall(mem_stall),
    .wb_trap(wb_trap)
  );

  hazard_unit u_hazard_unit (
    .ifid_valid(ifid_q.valid),
    .id_rs1_addr(id_rs1_addr),
    .id_rs2_addr(id_rs2_addr),
    .id_uses_rs1(id_uses_rs1),
    .id_uses_rs2(id_uses_rs2),
    .idex_valid(idex_q.valid),
    .idex_mem_read(idex_q.ctrl.mem_read),
    .idex_reg_write(idex_q.ctrl.reg_write),
    .idex_rd_addr(idex_q.rd_addr),
    .ex_redirect_taken(ex_redirect_taken),
    .ifid_flush(ifid_flush),
    .ifid_en(ifid_en),
    .idex_en(idex_en),
    .idex_flush(idex_flush),
    .memwb_en(memwb_en),
    .memwb_flush(memwb_flush),
    .exmem_en(exmem_en),
    .exmem_flush(exmem_flush),
    .wb_trap(wb_trap),
    .mem_stall(mem_stall),
    .halted(halted)
  );

  forwarding_unit u_fwd (
    .idex_valid(idex_q.valid),
    .idex_rs1_addr(idex_q.rs1_addr),
    .idex_rs2_addr(idex_q.rs2_addr),
    .exmem_reg_write(exmem_q.ctrl_m.reg_write),
    .exmem_mem_read(exmem_q.ctrl_m.mem_read),
    .exmem_rd_addr(exmem_q.rd_addr),
    .memwb_reg_write(memwb_q.ctrl_wb.reg_write),
    .memwb_rd_addr(memwb_q.rd_addr),
    .fwd_a_sel(fwd_a_sel),
    .fwd_b_sel(fwd_b_sel)
  );
endmodule
`default_nettype wire