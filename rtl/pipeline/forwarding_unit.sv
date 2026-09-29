`timescale 1ns/1ps

module forwarding_unit 
import single_pkg::*;
import pipeline_pkg::*;(
  input logic        idex_valid,
  input logic [4:0]  idex_rs1_addr,
  input logic [4:0]  idex_rs2_addr,

  input logic        exmem_reg_write,
  input logic        exmem_mem_read,  //for protection, if exmem is reading, then we should not forward to it.
  input logic [4:0]  exmem_rd_addr,

  input logic        memwb_reg_write,
  input logic [4:0]  memwb_rd_addr,

  output fwd_sel_e  fwd_a_sel,
  output fwd_sel_e  fwd_b_sel
);
  always_comb begin
    fwd_a_sel = FWD_NONE;
    fwd_b_sel = FWD_NONE;

    if (idex_valid) begin
      // Forwarding for rs1
      if (exmem_reg_write && (exmem_rd_addr != 5'd0) && (exmem_rd_addr == idex_rs1_addr) && !exmem_mem_read) begin
        fwd_a_sel = FWD_EXMEM;
      end else if (memwb_reg_write && (memwb_rd_addr != 5'd0) && (memwb_rd_addr == idex_rs1_addr)) begin
        fwd_a_sel = FWD_MEMWB;
      end

      // Forwarding for rs2
      if (exmem_reg_write && (exmem_rd_addr != 5'd0) && (exmem_rd_addr == idex_rs2_addr) && !exmem_mem_read) begin
        fwd_b_sel = FWD_EXMEM;
      end else if (memwb_reg_write && (memwb_rd_addr != 5'd0) && (memwb_rd_addr == idex_rs2_addr)) begin
        fwd_b_sel = FWD_MEMWB;
      end
    end
  end
endmodule
`default_nettype wire
