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

  input logic        ex_redirect_taken,

  output logic       pc_stall,
  output logic       ifid_flush,
  output logic       ifid_en,
  output logic       idex_flush
);
  logic load_use_hazard;

  always_comb begin
    load_use_hazard = ifid_valid && idex_valid && idex_mem_read && idex_reg_write &&
                      ((id_uses_rs1 && (id_rs1_addr == idex_rd_addr)) ||
                       (id_uses_rs2 && (id_rs2_addr == idex_rd_addr)));
    
    pc_stall = 1'b0;
    ifid_en = 1'b1;
    ifid_flush = 1'b0;
    idex_flush = 1'b0;

    if(ex_redirect_taken) begin
      ifid_flush = 1'b1;
      idex_flush = 1'b1;
    end else if(load_use_hazard) begin
      pc_stall = 1'b1;
      ifid_en = 1'b0;
      idex_flush = 1'b1;
    end
  end
endmodule

