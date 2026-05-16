`timescale 1ns/1ps

module pc(
  input  clk,
  input  rst,
  input      [31:0] pc_next,
  output reg [31:0] pc
);

  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'h00000000;
    end
    else begin
      pc <= pc_next;
    end
  end
endmodule

