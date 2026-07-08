`timescale 1ns/1ps

import single_pkg::*;

module alu(
  input  logic [31:0]     src_a,
  input  logic [31:0]     src_b,
  input  alu_ctrl_e       alu_ctrl,
  output logic [31:0]     result,
  output logic            zero
);

  always_comb begin
    case (alu_ctrl)
      ALU_ADD  : result = src_a + src_b;
      ALU_SUB  : result = src_a - src_b;
      ALU_AND  : result = src_a & src_b;
      ALU_OR   : result = src_a | src_b;
      ALU_XOR  : result = src_a ^ src_b;
      ALU_SLT  : result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
      ALU_SLTU : result = (src_a < src_b) ? 32'd1 : 32'd0;
      ALU_SLL  : result = src_a << src_b[4:0];
      ALU_SRL  : result = src_a >> src_b[4:0];
      ALU_SRA  : result = $signed(src_a) >>> src_b[4:0];
      default  : result = 32'b0;
    endcase
  end

  assign zero = (result == 32'b0);

endmodule
