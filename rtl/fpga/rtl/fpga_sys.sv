`timescale 1ns/1ps

module fpga_sys
import single_pkg::*;
#(
    parameter logic [31:0] RESET_PC  = 32'h8000_0000,
    parameter logic [31:0] RAM_BASE  = 32'h8000_0000,
    parameter int          RAM_AW    = 16,              // RAM = 2**16 B = 64 KB
    parameter logic [31:0] MMIO_BASE = 32'h1000_0000,
    parameter int          MMIO_AW   = 12,              // MMIO = 4 KB, see mmio_regs word_off
    parameter string       RAM_INIT  = "mmap_test.mem"
) (
    input logic clk,
    input logic rst,
    output logic halted,

    output exc_cause_e trap_cause_q,
    output logic [31:0] trap_pc_q,

    output logic tohost_seen,
    output logic [31:0] tohost,
    output logic pass,
    output logic fail,
    output logic mark_seen,
    output logic error_trap
);
    localparam int RAM_WORDS = 1 << (RAM_AW - 2);   // sys_ram depth = RAM region size / 4

    logic        imem_req_valid;
    logic [31:0] imem_req_addr;
    logic        imem_req_ready;

    logic        imem_rsp_ready;
    logic        imem_rsp_valid;
    logic [31:0] imem_rsp_rdata;

    logic        dmem_req_ready;
    logic        dmem_req_valid;
    logic        dmem_req_write;
    logic [31:0] dmem_req_addr;
    logic [31:0] dmem_req_wdata;
    logic [3:0]  dmem_req_wstrb;

    logic [31:0] dmem_rsp_rdata;
    logic        dmem_rsp_ready;
    logic        dmem_rsp_valid;

    logic        trap_valid;
    exc_cause_e  trap_cause;
    logic [31:0] trap_pc;
    assign error_trap = halted && trap_cause_q != EXC_BREAKPOINT;
    always_ff @( posedge clk ) begin
        if (rst) begin
            trap_cause_q <= exc_cause_e'(0); //only valid when halted
            trap_pc_q <= 32'h0;
        end else if (trap_valid) begin
            trap_cause_q <= exc_cause_e'(trap_cause);
            trap_pc_q <= trap_pc;
        end
    end
    // see the store process on led
    always_ff @( posedge clk ) begin
        if (rst) begin
            mark_seen <= 1'b0;
        end else begin
            if (dmem_req_valid && dmem_req_ready && dmem_req_write) begin
                mark_seen <= 1'b1;
            end
        end
    end

    assign pass = halted && trap_cause_q == EXC_BREAKPOINT && tohost_seen && tohost == 32'd1;
    assign fail = halted && !pass;

    core_5stage #(.RESET_PC(RESET_PC)) u_core (
        .clk           (clk),
        .rst           (rst),
        .imem_req_valid(imem_req_valid),
        .imem_req_ready(imem_req_ready),
        .imem_req_addr (imem_req_addr),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_ready(imem_rsp_ready),
        .imem_rsp_rdata(imem_rsp_rdata),
        .dmem_req_valid(dmem_req_valid),
        .dmem_req_ready(dmem_req_ready),
        .dmem_req_write(dmem_req_write),
        .dmem_req_addr (dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_wstrb(dmem_req_wstrb),
        .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_rdata(dmem_rsp_rdata),
        .trap_valid    (trap_valid),
        .trap_cause    (trap_cause),
        .trap_pc       (trap_pc),
        .halted        (halted)
    );

    sys_ram #(.DEPTH(RAM_WORDS), .INIT_FILE(RAM_INIT)) u_ram (
        .clk      (clk),
        .rst      (rst),
        .req_valid(ram_req_valid),
        .req_ready(ram_req_ready),
        .req_write(ram_req_write),
        .req_addr (ram_req_addr),
        .req_wdata(ram_req_wdata),
        .req_wstrb(ram_req_wstrb),
        .rsp_valid(ram_rsp_valid),
        .rsp_ready(ram_rsp_ready),
        .rsp_rdata(ram_rsp_rdata),
        .imem_req_valid(imem_req_valid),
        .imem_req_ready(imem_req_ready),
        .imem_req_addr (imem_req_addr),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_ready(imem_rsp_ready),
        .imem_rsp_rdata(imem_rsp_rdata)
    );
    endmodule
