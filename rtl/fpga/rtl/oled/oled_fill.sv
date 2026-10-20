`timescale 1ns/1ps
module oled_fill (
    input  logic clk, rst,
    input  logic start, // oled_seq done
    input  logic spi_busy,
    output logic spi_valid,
    output logic [7:0] spi_data,
    output logic dc
);
    // 6 window command bytes + 96 x 64 x 2 pixel bytes = 12294 bytes per frame
    logic [13:0] cnt; // 16384 > 12293
    assign spi_valid = start;

    always_comb begin
        dc = (cnt >= 14'd6);
        case (cnt)
            14'd0: spi_data = 8'h15;
            14'd1: spi_data = 8'h00;
            14'd2: spi_data = 8'h5F;
            14'd3: spi_data = 8'h75;
            14'd4: spi_data = 8'h00;
            14'd5: spi_data = 8'h3F;
            default: spi_data = cnt[0] ? 8'h00 : 8'hF8;
        endcase
    end

    always_ff @( posedge clk ) begin
        if (rst) begin
            cnt <= '0;
        end
        else begin
            if (spi_valid && !spi_busy) begin
                if (cnt == 14'd12293) cnt <= '0;
                else                  cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
