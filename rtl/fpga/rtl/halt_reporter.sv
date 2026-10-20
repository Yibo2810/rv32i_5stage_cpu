`timescale 1ns/1ps
module halt_reporter
import single_pkg::*;
#(
    parameter int PERIOD = 25_000_000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        halted,

    input  exc_cause_e  trap_cause_q,
    input  logic [31:0] trap_pc_q,
    input  logic [31:0] tohost,
    input  logic        pass,
    input  logic        bus_err,
    input  logic [31:0] bus_err_addr,

    output logic        tx_valid,
    output logic [7:0]  tx_data,
    input  logic        tx_busy
);
    localparam int LEN = 72;
    localparam int IW  = $clog2(LEN);
    localparam int CW  = $clog2(PERIOD + 1);

    function automatic logic [7:0] hex(input logic [3:0] n);
        return (n < 4'd10) ? 8'h30 + 8'(n) : 8'h57 + 8'(n);
    endfunction

    function automatic logic [63:0] hex8(input logic [31:0] v);
        for (int k = 0; k < 8; k++) hex8[8*k +: 8] = hex(v[4*k +: 4]);
    endfunction

    logic [8*LEN-1:0] line;
    assign line = {"\015\012HALT ", pass ? "PASS" : "FAIL",
                   " cause=",  hex(4'(trap_cause_q)),
                   " pc=",     hex8(trap_pc_q),
                   " tohost=", hex8(tohost),
                   " buserr=", hex({3'b0, bus_err}),
                   " addr=",   hex8(bus_err_addr),
                   "\015\012"};

    logic          sending;
    logic [IW-1:0] idx;
    logic [CW-1:0] wait_cnt;

    assign tx_valid = sending;
    assign tx_data  = line[8*(LEN-1-idx) +: 8];

    always_ff @(posedge clk) begin
        if (rst) begin
            sending  <= 1'b0;
            idx      <= '0;
            wait_cnt <= '0;
        end else if (!sending) begin
            if (halted) begin
                if (wait_cnt == '0) sending  <= 1'b1;
                else                wait_cnt <= wait_cnt - 1'b1;
            end
        end else if (!tx_busy) begin
            if (idx == IW'(LEN - 1)) begin
                sending  <= 1'b0;
                idx      <= '0;
                wait_cnt <= CW'(PERIOD);
            end else begin
                idx <= idx + 1'b1;
            end
        end
    end
endmodule
