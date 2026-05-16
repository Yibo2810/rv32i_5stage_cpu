`timescale 1ns/1ps

module regfile(
  input rst,
  input clk,
  input w_en,

  input [4:0] rs1_addr,
  input [4:0] rs2_addr,
  input [4:0] rd_addr,
  input [31:0] rd_data,

  output [31:0] rs1_data,
  output [31:0] rs2_data
);

  reg [31:0] regs[0:31];
  integer i;

  assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];

  always @(posedge clk ) begin
    if (rst) begin
      for (i = 0; i < 32; i = i + 1) begin
        regs[i] <= 32'b0;
      end
    end
    else if (w_en && rd_addr != 0) begin
      regs[rd_addr] <= rd_data;
    end

  end
endmodule

