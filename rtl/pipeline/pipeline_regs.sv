`timescale 1ns/1ps

module pipeline_regs import pipeline_pkg::*;(
    input  logic  clk,
    input  logic  rst,

    input  ifid_t  ifid_d,
    input  idex_t  idex_d,
    input  exmem_t exmem_d,
    input  memwb_t memwb_d,
    input  logic ifid_en, ifid_flush, idex_flush,

    output ifid_t  ifid_q,
    output idex_t  idex_q,
    output exmem_t exmem_q,
    output memwb_t memwb_q
);

    always_ff @(posedge clk) begin
        if (rst) begin
            ifid_q  <= '0;
            idex_q  <= '0;
            exmem_q <= '0;
            memwb_q <= '0;
        end else begin
            if (ifid_flush) begin
                ifid_q <= '0;
            end else if (ifid_en) begin
                ifid_q <= ifid_d;
            end
            if (idex_flush) begin
                idex_q <= '0;
            end else begin
                idex_q <= idex_d;
            end
            exmem_q <= exmem_d;
            memwb_q <= memwb_d;
        end
    end

endmodule