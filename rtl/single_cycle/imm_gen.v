`timescale 1ns/1ps
`include "rv32i_defs.vh"

module imm_gen(
  input      [31:0] instr,
  input      [2:0]  imm_sel,
  output reg [31:0] imm
);

  always @(*) begin
    case (imm_sel)
      `RV32I_IMM_NONE :imm = 32'b0;
      `RV32I_IMM_B : imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      `RV32I_IMM_I : imm = {{20{instr[31]}}, instr[31:20]};
      `RV32I_IMM_S : imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      `RV32I_IMM_U : imm = {{11{instr[31]}}, instr[31:12]};
      `RV32I_IMM_J : imm = {{11{instr[31]}}, instr[31], instr[18:12], instr[19], instr[30:20]};
      default: imm = 32'b0;
    endcase
  end

endmodule
