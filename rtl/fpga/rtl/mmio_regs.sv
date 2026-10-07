`timescale 1ns/1ps
module mmio_regs (
  input  logic        clk, rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic        req_write,
  input  logic [31:0] req_addr,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata,

  output logic        tohost_seen,
  output logic [31:0] tohost
);

    logic       fire;
    logic [9:0] word_off;                 // 4 KB = fpga_sys MMIO_AW (12): [MMIO_AW-1:2]
    assign fire     = req_valid && req_ready;
    assign word_off = req_addr[11:2];
    localparam logic [9:0] OFF_TOHOST = 10'h040;   // 0x100 >> 2  tohost change to 0x100
    assign req_ready = 1'b1;

    always_ff @( posedge clk ) begin
        if (rst) begin
            tohost_seen <= 1'b0;
            tohost <= 32'b0;
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'b0;
        end else begin
            rsp_valid <= fire;
            if (fire && req_write && word_off == OFF_TOHOST && req_wstrb == 4'b1111 && !tohost_seen) begin
                tohost <= req_wdata;
                tohost_seen <= 1'b1;
            end
            if (fire && !req_write) begin
                case(word_off)
                    OFF_TOHOST: rsp_rdata <= tohost;
                    default:    rsp_rdata <= 32'b0;
                endcase
            end
        end
    end
endmodule