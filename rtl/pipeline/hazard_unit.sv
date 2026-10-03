`timescale 1ns/1ps

module hazard_unit
import single_pkg::*;
import pipeline_pkg::*;(
  input logic        ifid_valid,
  input logic [4:0]  id_rs1_addr,
  input logic [4:0]  id_rs2_addr,
  input logic        id_uses_rs1,
  input logic        id_uses_rs2,

  input logic        idex_valid,
  input logic        idex_mem_read,
  input logic        idex_reg_write,
  input logic [4:0]  idex_rd_addr,
  input logic        wb_trap,
  input logic        mem_stall,
  input logic        halted,

  input logic        ex_redirect_taken,

  output logic       ifid_flush,
  output logic       ifid_en,
  output logic       idex_en,
  output logic       idex_flush,
  output logic       memwb_en,
  output logic       memwb_flush,
  output logic       exmem_en,
  output logic       exmem_flush
);
  logic load_use_hazard;

  always_comb begin
    ifid_en  = 1'b1;  ifid_flush  = 1'b0;
    idex_en  = 1'b1;  idex_flush  = 1'b0;
    exmem_en = 1'b1;  exmem_flush = 1'b0;
    memwb_en = 1'b1;  memwb_flush = 1'b0;
    load_use_hazard = ifid_valid && idex_valid && idex_mem_read && idex_reg_write &&
                      ((id_uses_rs1 && (id_rs1_addr == idex_rd_addr)) ||
                       (id_uses_rs2 && (id_rs2_addr == idex_rd_addr)));
    
    if (wb_trap || halted) begin
      ifid_flush  = 1'b1;
      idex_flush  = 1'b1;
      exmem_flush = 1'b1;
      memwb_flush = 1'b1;
    end else if (mem_stall) begin
      ifid_en  = 1'b0;
      idex_en  = 1'b0;
      exmem_en = 1'b0;
      memwb_en = 1'b0;
    end else if (ex_redirect_taken) begin
      ifid_flush = 1'b1;
      idex_flush = 1'b1;
    end else if (load_use_hazard) begin
      ifid_en    = 1'b0;
      idex_flush = 1'b1;
    end
  end
endmodule
`default_nettype wire
