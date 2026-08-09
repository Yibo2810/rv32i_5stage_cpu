`timescale 1ns/1ps

import pipeline_pkg::*;

module pipeline_regs (
    input  logic  clk,
    input  logic  rst,

    input  ifid_t  ifid_d,
    input  idex_t  idex_d,
    input  exmem_t exmem_d,
    input  memwb_t memwb_d,

    output ifid_t  ifid_q,
    output idex_t  idex_q,
    output exmem_t exmem_q,
    output memwb_t memwb_q
);

    always_ff @(posedge clk or posedge rst) begin //asynchronous reset, 
        if (rst) begin
            ifid_q  <= '0;
            idex_q  <= '0;
            exmem_q <= '0;
            memwb_q <= '0;
        end else begin
            ifid_q  <= ifid_d;
            idex_q  <= idex_d;
            exmem_q <= exmem_d;
            memwb_q <= memwb_d;
        end
    end

endmodule