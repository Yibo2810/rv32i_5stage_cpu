`timescale 1ns/1ps
module imem_rom #(
    parameter int DEPTH = 256,
    parameter string INIT_FILE = ""
) (
    input   logic        imem_req_valid,
    input   logic [31:0] imem_req_addr,
    output  logic        imem_req_ready,

    input   logic        imem_rsp_ready,
    output  logic        imem_rsp_valid,
    output  logic [31:0] imem_rsp_rdata,
);
    localparam int ADDR_W = $clog2(DEPTH);
    logic [ADDR_W-1:0] idx;
    logic imem_req_fire;
    logic imem_rsp_fire;
    assign imem_req_fire = imem_req_ready && imem_req_valid;
    assign imem_rsp_fire = imem_rsp_ready && imem_rsp_valid;
    assign imem_req_ready = !imem_rsp_valid || imem_rsp_ready;

    always_comb begin
        if (imem_rsp_fire) imem_rsp_valid

    (* rom_style = "distributed" *)
    logic [31:0] rom [0:DEPTH-1];

    assign idx = addr[ADDR_W+1:2];
    assign rdata = rom[idx];

    initial begin
        $readmemh(INIT_FILE, rom);
    end
endmodule