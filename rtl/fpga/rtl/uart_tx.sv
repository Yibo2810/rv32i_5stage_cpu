`timescale 1ns/1ps
module uart_tx #(
    parameter int CLKS_PER_BIT = 4
) (
    input  logic clk, rst,
    input  logic tx_valid,
    input  logic [7:0] tx_data,
    output logic tx_busy,
    output logic tx
);
    logic [9:0] shift;
    localparam int AW = $clog2(CLKS_PER_BIT);
    logic [AW-1:0] clk_cnt ;

    always_ff @( posedge clk ) begin
        if (rst) begin
            tx <= 1'b1;
            tx_busy <= 1'b0;
            clk_cnt <= '0;
            shift <= '0;
        end
        else begin
            if (tx_busy == 1'b0) begin
                tx <= 1'b1;
                if (tx_valid == 1'b1) begin
                    shift <= {1'b1, tx_data, 1'b0};
                    clk_cnt <= '0;
                    tx_busy <= 1'b1;
                end
            end

            if (tx_busy == 1'b1) begin
                tx <= shift[0];
                clk_cnt <= clk_cnt + 1'b1;
                if (clk_cnt == AW'(CLKS_PER_BIT - 1)) begin
                    clk_cnt <= '0;
                    shift <= shift >> 1;
                    if (shift == 10'b1) begin
                        tx_busy <= 1'b0;
                    end
                end
            end
        end
    end
endmodule