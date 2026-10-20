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
    output logic oled_pmoden
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

    oled_fill u_fill (
        .clk(clk),
        .rst(rst),
        .start(done),
        .spi_busy(spi_busy),
        .spi_valid(f_valid),
        .spi_data(f_data),
        .dc(f_dc)
    );

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
endmodule
