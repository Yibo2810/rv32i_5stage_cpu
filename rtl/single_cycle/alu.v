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
      `RV32I_ALU_ADD  : result = src_a + src_b;
      `RV32I_ALU_SUB  : result = src_a - src_b;
      `RV32I_ALU_AND  : result = src_a & src_b;
      `RV32I_ALU_OR   : result = src_a | src_b;
      `RV32I_ALU_XOR  : result = src_a ^ src_b;
      `RV32I_ALU_SLT  : result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
      `RV32I_ALU_SLTU : result = (src_a < src_b) ? 32'd1 : 32'd0;
      `RV32I_ALU_SLL  : result = src_a << src_b[4:0];
      `RV32I_ALU_SRL  : result = src_a >> src_b[4:0];
      `RV32I_ALU_SRA  : result = $signed(src_a) >>> src_b[4:0];
      default : result = 32'b0;
    endcase
  end

  assign zero = (result == 32'b0);

endmodule

