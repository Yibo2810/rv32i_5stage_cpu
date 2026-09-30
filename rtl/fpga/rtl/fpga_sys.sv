`timescale 1ns/1ps

module fpga_sys
import single_pkg::*;
#(
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 256,
    parameter string IMEM_INIT = "rtl/fpga/build/hazard_test.mem",
    parameter logic [31:0] TOHOST_ADDR = 32'h0000_03FC
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
    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;

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

    always_ff @( posedge clk ) begin
        if (rst) begin
            tohost_seen <= 1'b0;
            tohost <= 32'b0;
        end else begin
            if (dmem_req_valid && dmem_req_ready && dmem_req_write && dmem_req_addr == TOHOST_ADDR && dmem_req_wstrb == 4'b1111 && !tohost_seen) begin
                tohost <= dmem_req_wdata;
                tohost_seen <= 1'b1;
            end
        end
    end

    assign pass = halted && trap_cause_q == EXC_BREAKPOINT && tohost_seen && tohost == 32'd1;
    assign fail = halted && !pass;

    core_5stage u_core (
        .clk           (clk),
        .rst           (rst),
        .imem_addr     (imem_addr),
        .imem_rdata    (imem_rdata),
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

    dmem_bram #(.DEPTH(DMEM_WORDS)) u_dmem (
        .clk      (clk),
        .rst      (rst),
        .req_valid(dmem_req_valid),
        .req_ready(dmem_req_ready),
        .req_write(dmem_req_write),
        .req_addr (dmem_req_addr),
        .req_wdata(dmem_req_wdata),
        .req_wstrb(dmem_req_wstrb),
        .rsp_valid(dmem_rsp_valid),
        .rsp_ready(dmem_rsp_ready),
        .rsp_rdata(dmem_rsp_rdata)
    );

    imem_rom #(.DEPTH(IMEM_WORDS), .INIT_FILE(IMEM_INIT)) u_imem (
        .addr(imem_addr),
        .rdata(imem_rdata)
    );
    endmodule
