`timescale 1ns/1ps

import single_pkg::*;

module imm_gen(
  input  logic [31:0]    instr,
  input  imm_sel_e       imm_sel,
  output logic [31:0]    imm
);

  always_comb begin
    case (imm_sel)
      IMM_NONE :imm = 32'b0;
      IMM_B : imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      IMM_I : imm = {{20{instr[31]}}, instr[31:20]};
      IMM_S : imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      IMM_U : imm = {{12{instr[31]}}, instr[31:12]};
      IMM_J : imm = {{12{instr[31]}}, instr[31], instr[18:12], instr[19], instr[30:20]};
      default: imm = 32'b0;
    endcase
  end

endmodule
