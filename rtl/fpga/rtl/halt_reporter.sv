`timescale 1ns/1ps
module halt_reporter
import peripherals::*;
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
    localparam int LEN = 72;                    // have 72 character
    localparam int IW  = $clog2(LEN);           // need 7-bit (2^6=64)
    localparam int CW  = $clog2(PERIOD + 1);

    

    logic [8*LEN-1:0] line;  // logic[72*8-1:0]

    assign line = {"\015\012HALT ", pass ? "PASS" : "FAIL",
                   " cause=",  hex_ch(4'(trap_cause_q)),
                   " pc=",     hex8_str(trap_pc_q),
                   " tohost=", hex8_str(tohost),
                   " buserr=", hex_ch({3'b0, bus_err}),
                   " addr=",   hex8_str(bus_err_addr),
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
