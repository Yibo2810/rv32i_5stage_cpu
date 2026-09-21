module pipeline_sva_bind import pipeline_pkg::*; (
    input logic clk, rst,
    input logic pc_stall,
    input logic [31:0] imem_addr,
    input idex_t    idex_q,
    input exmem_t   exmem_q,
    input memwb_t   memwb_q,
    input logic     wb_retire
);
    default clocking @(posedge clk); endclocking
    default disable iff (rst);

    bind core_5stage pipeline_sva_bind u_sva(
        .clk(clk),
        .rst(rst),
        .pc_stall(pc_stall),
        .imem_addr(imem_addr),
        .idex_q(idex_q),
        .exmem_q(exmem_q),
        .memwb_q(memwb_q),
        .wb_retire(wb_retire)
    );
endmodule