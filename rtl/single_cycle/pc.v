`timescale 1ns/1ps

module pc(
  input  clk,
  input  rst,
  input      [31:0] pc_next,
  output reg [31:0] pc
);
  parameter RESET_PC = 32'h00000000;
  always @(posedge clk) begin
    if (rst) begin
      pc <= RESET_PC;
    end
    else begin
      pc <= pc_next;
    end
  end
endmodule

