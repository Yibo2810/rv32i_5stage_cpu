`timescale 1ns/1ps

module pipeline_memory (
    pipeline_probe_if.bram p
);
    localparam int          IMEM_WORDS = 256;
    localparam logic [31:0] EBREAK     = 32'h0010_0073;

    logic [31:0] imem [0:IMEM_WORDS-1];

    assign p.imem_rdata = imem[p.imem_addr[9:2]];

    task automatic load_hex(input string path);
        foreach (imem[i]) imem[i] = EBREAK;
        $readmemh(path, imem);
    endtask

    function automatic logic [31:0] peek_dmem(input logic [31:0] addr);
        return u_dmem.mem[addr[9:2]];
    endfunction

    dmem_bram #(.DEPTH(256)) u_dmem (
        .clk      (p.clk),
        .rst      (p.rst),
        .req_valid(p.dmem_req_valid),
        .req_ready(p.dmem_req_ready),
        .req_write(p.dmem_req_write),
        .req_addr (p.dmem_req_addr),
        .req_wdata(p.dmem_req_wdata),
        .req_wstrb(p.dmem_req_wstrb),
        .rsp_valid(p.dmem_rsp_valid),
        .rsp_ready(p.dmem_rsp_ready),
        .rsp_rdata(p.dmem_rsp_rdata)
    );
endmodule