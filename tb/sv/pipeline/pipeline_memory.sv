`timescale 1ns/1ps

module pipeline_memory (
    pipeline_probe_if.bram p
);
    localparam logic [31:0] EBREAK     = 32'h0010_0073;

    task automatic clear_dmem();
        foreach (u_dmem.mem[i]) u_dmem.mem[i] = 32'b0;
    endtask
    
    task automatic init_mem();
        foreach (u_imem.mem[i]) u_imem.mem[i] = 32'h0010_0073;
    endtask

    function automatic void reseed(input int s);
        u_imem.reseed(s);
    endfunction

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

    imem_bram #(.DEPTH(256)) u_imem (
        .clk      (p.clk),
        .rst      (p.rst),
        .req_valid(p.imem_req_valid),
        .req_ready(p.imem_req_ready),
        .req_addr (p.imem_req_addr),
        .rsp_valid(p.imem_rsp_valid),
        .rsp_ready(p.imem_rsp_ready),
        .rsp_rdata(p.imem_rsp_rdata)
    );
endmodule