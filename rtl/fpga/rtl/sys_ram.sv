`timescale 1ns/1ps
module sys_ram #(
    parameter int DEPTH = 1024,
    parameter string INIT_FILE = ""
) (
    input   logic        clk, rst,
    // IMEM
    input   logic        imem_req_valid,
    input   logic [31:0] imem_req_addr,
    output  logic        imem_req_ready,

    input   logic        imem_rsp_ready,
    output  logic        imem_rsp_valid,
    output  logic [31:0] imem_rsp_rdata,

    // DMEM
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr, req_wdata,
    input  logic [3:0]  req_wstrb,
    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic [31:0] rsp_rdata
);

    // INITIAL
    (* ram_style = "block" *)
    logic [31:0]   mem [DEPTH];

    localparam int AW = $clog2(DEPTH);
    logic [AW-1:0] d_idx;
    logic [AW-1:0] i_idx;
    initial begin
        for (int k = 0; k < DEPTH; k++) mem[k] = 32'b0;
        $readmemh(INIT_FILE, mem);
    end
    // ================================================================
    // IMEM
    // ================================================================
    assign i_idx = imem_req_addr[AW+1:2];
    logic imem_req_fire;
    logic imem_rsp_fire;
    assign imem_req_fire = imem_req_ready && imem_req_valid;
    assign imem_rsp_fire = imem_rsp_ready && imem_rsp_valid;
    assign imem_req_ready = !imem_rsp_valid || imem_rsp_ready;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            imem_rsp_valid <= 1'b0;
        end else begin
        if (imem_rsp_fire) begin
            imem_rsp_valid <= 1'b0;
        end
        if (imem_req_fire) begin
            imem_rsp_valid <= 1'b1;
            imem_rsp_rdata <= mem[idx];
        end
        end
    end
    // ================================================================
    // DMEM
    // ================================================================
    logic          fire;

    assign req_ready = 1'b1;
    assign d_idx       = req_addr[AW+1:2];
    assign fire      = req_valid && req_ready;
    
    always @(posedge clk) begin
        if (fire && req_write)
        for (int b = 0; b < 4; b++)
            if (req_wstrb[b]) mem[idx][8*b +: 8] <= req_wdata[8*b +: 8];
        if (fire && !req_write)
        rsp_rdata <= mem[idx];
    end

    always_ff @(posedge clk) begin
        if (rst) rsp_valid <= 1'b0;
        else     rsp_valid <= fire;
    end
endmodule