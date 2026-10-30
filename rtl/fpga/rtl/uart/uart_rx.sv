`timescale 1ns/1ps
module uart_rx 
import peripherals::*;
#( parameter int CLKS_PER_BIT = 8 ) (
    input  logic rst, clk,
    input  logic rx,
    output logic rx_valid,
    output logic [7:0] rx_data,
    output logic frame_err
);
    localparam int AW = $clog2(CLKS_PER_BIT);
    (* ASYNC_REG = "TRUE" *) logic rx_s, rx_meta;
    logic [AW-1:0] clk_cnt;
    logic [2:0] bit_idx;
    logic [7:0] shift;

    typedef enum logic [1:0]{
        IDLE = 2'b00,
        START = 2'b01,
        DATA = 2'b10,
        STOP = 2'b11
    } state_e;
    state_e state;

    always_ff @( posedge clk ) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_s <= 1'b1;            
        end else begin
            rx_meta <= rx;
            rx_s <= rx_meta;
        end
    end

    always_ff @( posedge clk ) begin
        if (rst) begin
            clk_cnt <= '0;
            bit_idx <= 3'b0;
            shift <= 8'b0;
            state <= IDLE;
            rx_valid <= 1'b0;
            rx_data <= 8'b0;
            frame_err <= 1'b0;
        end
        else begin
            clk_cnt <= clk_cnt + 1'b1;
            case (state)
                IDLE: begin
                    rx_valid <= 1'b0;
                    if (rx_s == 1'b0) begin
                        clk_cnt <= '0;
                        state <= START;
                    end
                end

                START: begin
                    if (clk_cnt == CLKS_PER_BIT/2 - 1) begin
                        if (rx_s == 1'b0) begin
                            state <= DATA;
                            clk_cnt <= '0;
                        end 
                        else state <= IDLE;
                    end
                end

                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        bit_idx <= bit_idx + 1'b1;
                        shift <= {rx_s, shift[7:1]};
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                            bit_idx <= 3'b0;
                        end
                    end
                end

                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        frame_err <= !rx_s;
                        clk_cnt <= '0;
                        rx_data <= shift;
                        rx_valid <= 1'b1;
                        state <= IDLE;
                    end
                end
                default: frame_err <= 1'b1;
            endcase
        end
    end
endmodule