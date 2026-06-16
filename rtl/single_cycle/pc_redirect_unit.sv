`timescale 1ns/1ps
import single_pkg::*;
module pc_redirect_unit(
    input  logic [31:0] pc_current,
    input  logic [31:0] imm,
    input  logic [31:0] alu_result,

    input logic            branch_taken,
    input logic            jump_and_link,
    input logic            side_effect_ok,
    input pc_target_sel_e  pc_target_sel,

    output logic [31:0] pc_plus_4,
    output logic [31:0] pc_next
);
    logic [31:0] pc_imm_target;
    logic [31:0] pc_alu_target;
    logic [31:0] redirect_target;
    logic        redirect;

     // Determine branch target based on control signals
    assign pc_plus_4 = pc_current + 32'd4;
    assign pc_imm_target = pc_current + imm;
    assign pc_alu_target = {alu_result[31:1], 1'b0};


    assign redirect = side_effect_ok && (branch_taken || jump_and_link);
    assign pc_next = redirect ? redirect_target : pc_plus_4;

    always_comb begin
        case (pc_target_sel)
            PC_TARGET_ALU: redirect_target = pc_alu_target;
            PC_TARGET_PC_IMM: redirect_target = pc_imm_target;
            default: redirect_target = pc_plus_4;
        endcase
    end
endmodule
