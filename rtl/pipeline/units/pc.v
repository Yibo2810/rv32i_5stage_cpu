`timescale 1ns/1ps

module pc #(parameter [31:0] RESET_PC = 32'h0000_0000)(
  input  clk,
  input  rst,
  input      [31:0] pc_next,
  output reg [31:0] pc
);
  always @(posedge clk) begin
    if (rst) begin
      pc <= RESET_PC;
    end
    else begin
      pc <= pc_next;
    end
  end
endmodule

