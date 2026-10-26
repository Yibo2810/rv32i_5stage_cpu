`timescale 1ns/1ps
module oled_render 
import peripherals::*;
(
    input  logic clk, rst,
    input  logic start, // oled_seq done
    input  logic spi_busy,
    output logic spi_valid,
    output logic [7:0] spi_data,
    output logic dc,

    // CPU write charater
    input logic txt_wr,
    input logic [6:0] txt_idx,
    input logic [7:0] txt_data,
    // CPU write color
    input logic col_wr,
    input logic [2:0] col_idx,
    input logic [15:0] col_data,
    // ================================
    // trap/halt, display when panic
    input logic halted, pass,
    input logic [3:0] trap_cause_q,
    input logic [31:0] trap_pc_q,
    input logic [31:0] tohost,
    input logic bus_err,
    input logic [31:0] bus_err_addr
    // ================================ 
);
    logic [2:0] cnt;
    logic [6:0] x;
    logic [5:0] y;
    logic [15:0] pix;
    logic       lo;

    typedef enum logic {
        WIN = 1'b0,
        PIX = 1'b1
    } state_t;
    state_t state;

    logic [7:0] ch, bits;
    logic [15:0] fg, bg;
    logic [2:0] row;
    logic [3:0] col;
    logic [2:0] gx, gy;

    assign col = x[6:3];
    assign row = y[5:3];
    assign gx  = x[2:0];
    assign gy  = y[2:0];
    assign spi_valid = start;
    assign pix = bits[gx] ? fg : bg;

    always_comb begin
        dc = 1'b0;
        spi_data = 8'h00;
        if (state == WIN) begin
            dc = 1'b0;
            case (cnt)
                3'd0: spi_data = 8'h15;
                3'd1: spi_data = 8'h00;
                3'd2: spi_data = 8'h5F;
                3'd3: spi_data = 8'h75;
                3'd4: spi_data = 8'h00;
                3'd5: spi_data = 8'h3F;
                default: ;
            endcase
        end
        if (state == PIX) begin
            dc = 1'b1;
            spi_data = lo ? pix[7:0] : pix[15:8];
        end
    end

    always_ff @( posedge clk ) begin
        if (rst) begin
            cnt <= '0;
            x  <= '0;
            y  <= '0;
            lo <= 1'b0;
            state <= WIN;
        end
        else begin
            if (spi_valid && !spi_busy) begin
                case (state)
                    WIN: begin
                        if (cnt < 3'd5) cnt <= cnt + 1'b1;
                        if (cnt == 3'd5) begin
                            state <= PIX;
                            x  <= '0;
                            y  <= '0;
                            lo <= '0;
                        end
                    end

                    PIX: begin
                        if (lo == 0) lo <= 1'b1;
                        else begin
                            if (lo == 1) begin
                                if (x < 7'd95) begin
                                    x <= x + 1'b1;
                                    lo <= 1'b0;
                                end
                                else begin
                                    if (y < 6'd63) begin
                                        x <= '0;
                                        y <= y + 1'b1;
                                        lo <= 1'b0;
                                    end
                                    else begin
                                        state <= WIN;
                                        cnt <= '0;
                                    end
                                end
                            end
                        end
                    end
                    default: ;
                endcase   
            end
        end
    end

    oled_text u_text(
        .clk(clk),
        .rst(rst),

        .txt_wr  (txt_wr),
        .txt_idx (txt_idx),
        .txt_data(txt_data),
        .col_wr  (col_wr),
        .col_idx (col_idx),
        .col_data(col_data),

        .halted      (halted),
        .trap_cause_q(trap_cause_q),
        .trap_pc_q   (trap_pc_q),
        .tohost      (tohost),
        .pass        (pass),
        .bus_err     (bus_err),
        .bus_err_addr(bus_err_addr),

        .ch(ch),
        .bg(bg),
        .fg(fg),
        .row(row),
        .col(col)
    );

    oled_font u_font(
        .ch(ch),
        .gy(gy),
        .bits(bits)
    );
endmodule