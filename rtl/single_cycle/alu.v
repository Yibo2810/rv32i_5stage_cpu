`timescale 1ns/1ps
`include "rv32i_defs.vh"

module alu(
  input      [31:0] src_a,
  input      [31:0] src_b,
  input      [3:0]  alu_ctrl,
  output reg [31:0] result,
  output      zero
);

  always @(*) begin
    case (alu_ctrl)
      `RV32I_ALU_ADD : result = src_a + src_b;
      `RV32I_ALU_SUB : result = src_a - src_b;
      default : result = 32'b0;
    endcase
  end

  assign zero = (result == 32'b0);

endmodule

