`timescale 1ns/1ps
module imem_rom #(
    parameter int DEPTH = 256,
    parameter string INIT_FILE = ""
) (
    input   logic        clk, rst,
    input   logic        imem_req_valid,
    input   logic [31:0] imem_req_addr,
    output  logic        imem_req_ready,

    input   logic        imem_rsp_ready,
    output  logic        imem_rsp_valid,
    output  logic [31:0] imem_rsp_rdata
);
    localparam int ADDR_W = $clog2(DEPTH);
    logic [ADDR_W-1:0] idx;
    (* rom_style = "block" *)
    logic [31:0] rom [0:DEPTH-1];
    assign idx = imem_req_addr[ADDR_W+1:2];
    logic imem_req_fire;
    logic imem_rsp_fire;
    assign imem_req_fire = imem_req_ready && imem_req_valid;
    assign imem_rsp_fire = imem_rsp_ready && imem_rsp_valid;
    assign imem_req_ready = !imem_rsp_valid || imem_rsp_ready;

    initial begin
        $readmemh(INIT_FILE, rom);
    end
    
    always_ff @(posedge clk) begin
        if (rst) begin
            imem_rsp_valid <= 1'b0;
        end else begin
        if (imem_rsp_fire) begin
            imem_rsp_valid <= 1'b0;
        end
        if (imem_req_fire) begin
            imem_rsp_valid <= 1'b1;
            imem_rsp_rdata <= rom[idx];
        end
        end
    end
endmodule