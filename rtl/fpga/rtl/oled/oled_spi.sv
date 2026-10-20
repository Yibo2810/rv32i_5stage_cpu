`timescale 1ns/1ps
module oled_spi #(
    parameter int HALF = 2
) (
    input  logic clk, rst,
    input  logic valid,
    input  logic [7:0] data,
    input  logic dc,
    output logic busy,
    output logic dc_o,
    output logic mosi,
    output logic cs_n,
    output logic sclk
);
    localparam AW = $clog2(HALF);
    logic [7:0] shift;
    logic [2:0] bit_cnt;
    logic [AW-1:0] half_cnt;
    logic first;

    always_ff @( posedge clk ) begin
        if (rst) begin
            half_cnt <= '0;
            busy <= 1'b0;
            bit_cnt <= 3'b0;
            dc_o <= 1'b0;
            shift <= '0;
            cs_n <= 1'b1;
            sclk <= 1'b1;
            first <= 1'b0;
        end
        else begin
            if (!busy && valid) begin
                cs_n <= 1'b0;
                dc_o <= dc;
                mosi <= data[7];
                shift <= {data[6:0], 1'b0};
                busy <= 1'b1;
                first <= 1'b1;
                half_cnt <= '0;
                bit_cnt <= 3'b0;
            end
            if (busy == 1'b1) begin
                half_cnt <= half_cnt + 1'b1;
                if (half_cnt == HALF-1) begin
                    half_cnt <= '0;
                    if (sclk == 1'b0) sclk <= 1'b1;
                    else if (first) begin
                        sclk <= 1'b0;
                        first <= 1'b0;
                    end
                    else if (bit_cnt == 3'd7) begin
                        cs_n <= 1'b1;
                        busy <= 1'b0;
                    end
                    else begin
                        shift <= shift << 1;
                        bit_cnt <= bit_cnt + 1'b1;
                        mosi <= shift[7];
                        sclk <= 1'b0;
                    end
                end
            end
        end
    end
endmodule