`timescale 1ns/1ps
module dmem_bram #(parameter int DEPTH = 1024) (    // words
  input  logic        clk, rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic        req_write,
  input  logic [31:0] req_addr, req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata
);
  localparam int AW = $clog2(DEPTH);
  logic [31:0]   mem [DEPTH];
  logic [AW-1:0] idx;
  logic          fire;

  assign req_ready = 1'b1;
  assign idx       = req_addr[AW+1:2];
  assign fire      = req_valid && req_ready;

  initial for (int k = 0; k < DEPTH; k++) mem[k] = 32'b0;
  
  always @(posedge clk) begin
    if (fire && req_write)
      for (int b = 0; b < 4; b++)
        if (req_wstrb[b]) mem[idx][8*b +: 8] <= req_wdata[8*b +: 8];
    if (fire && !req_write)
      rsp_rdata <= mem[idx];
  end

  always_ff @(posedge clk) begin
    if (rst) rsp_valid <= 1'b0;
    else     rsp_valid <= fire;
  end
endmodule
`default_nettype wire