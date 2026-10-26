`timescale 1ns/1ps
module oled_ctrl
#(
    parameter int MS_CYCLES = 25_000,
    parameter int HALF = 2
    ) (
    input logic clk, rst,
    output logic oled_cs_n,
    output logic oled_mosi,
    output logic oled_sclk,
    output logic oled_dc,
    output logic oled_res_n,
    output logic oled_vccen,
    output logic oled_pmoden,

    // CPU write charater
    input logic oled_txt_wr,
    input logic [6:0] oled_txt_idx,
    input logic [7:0] oled_txt_data,
    // CPU write color
    input logic oled_col_wr,
    input logic [2:0] oled_col_idx,
    input logic [15:0] oled_col_data,

    // trap/halt, display when panic
    input logic halted, pass,
    input logic [3:0] trap_cause_q,
    input logic [31:0] trap_pc_q,
    input logic [31:0] tohost,
    input logic bus_err,
    input logic [31:0] bus_err_addr
);
    logic       done;
    logic       spi_busy;
    logic       s_valid;
    logic [7:0] s_data;
    logic       f_valid;
    logic [7:0] f_data;
    logic       f_dc;

    logic       spi_valid;
    logic [7:0] spi_data;
    logic       spi_dc;
    assign spi_valid = done ? f_valid : s_valid;
    assign spi_data  = done ? f_data  : s_data;
    assign spi_dc    = done ? f_dc    : 1'b0;

    oled_seq #(.MS_CYCLES(MS_CYCLES)) u_seq  (
        .clk(clk),
        .rst(rst),
        .spi_valid(s_valid),
        .spi_data(s_data),
        .spi_busy(spi_busy),
        .pmoden(oled_pmoden),
        .res_n(oled_res_n),
        .vccen(oled_vccen),
        .done(done)
    );

    oled_spi #(.HALF(HALF)) u_spi (
        .clk(clk),
        .rst(rst),
        .valid(spi_valid),
        .data(spi_data),
        .dc(spi_dc),
        .busy(spi_busy),
        .dc_o(oled_dc),
        .mosi(oled_mosi),
        .cs_n(oled_cs_n),
        .sclk(oled_sclk)
    );

    oled_render u_render(
        .clk(clk),
        .rst(rst),
        .start(done),
        .spi_busy(spi_busy),
        .spi_valid(f_valid),
        .spi_data(f_data),
        .dc(f_dc),

        .txt_wr  (oled_txt_wr),
        .txt_idx (oled_txt_idx),
        .txt_data(oled_txt_data),
        .col_wr  (oled_col_wr),
        .col_idx (oled_col_idx),
        .col_data(oled_col_data),

        .halted      (halted),
        .trap_cause_q(trap_cause_q),
        .trap_pc_q   (trap_pc_q),
        .tohost      (tohost),
        .pass        (pass),
        .bus_err     (bus_err),
        .bus_err_addr(bus_err_addr)
    );
endmodule
