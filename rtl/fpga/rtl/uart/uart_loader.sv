`timescale 1ns/1ps
module uart_loader 
import peripherals::*;
(
    input logic clk, rst,
    input logic load_mode,         // SW[2]
    input logic rx_valid,
    input logic [7:0] rx_data,

    output logic loading,          // Keep rst
    output logic load_err,         // Validation failed
    // Send to DMEM
    output logic wr_valid,
    output logic [31:0] wr_addr,
    output logic [31:0] wr_data,
    output logic [3:0]  wr_strb
);
    typedef enum logic [2:0] { 
        IDLE  = 3'd0,
        MAGIC = 3'd1,
        LEN   = 3'd2,
        DATA  = 3'd3,
        SUM   = 3'd4,
        DONE  = 3'd5,
        ERR   = 3'd6
    } state_e;
    state_e state;

    logic [1:0] cnt;
    logic [31:0] len;
    logic [31:0] off;   // address, from 0 to 65535
    logic [31:0] sum;
    assign wr_addr = off;
    assign loading = (!(state == IDLE) && load_mode && !(state == DONE));
    assign wr_strb = 4'b1111;
    assign load_err = (state == ERR);

    logic [31:0] len_next;
    assign len_next = {rx_data, len[31:8]};
    
    logic [31:0] word;
    assign wr_valid = (state == DATA) && (rx_valid == 1'b1) && (off[1:0] == 2'b11);
    assign wr_data  = {rx_data, word[31:8]};

    typedef enum logic [7:0] { 
        R = 8'h52,
        V = 8'h56,
        L = 8'h4C,
        D = 8'h44,
        WAIT = 8'h00
    } rvld_e;
    rvld_e rvld;

    always_ff @( posedge clk ) begin
        if (rst) begin
            state <= IDLE;
            cnt <= 2'b0;
            len <= 32'b0;
            off <= 16'b0;
            rvld <= WAIT;
        end
        else begin
            if (!load_mode) state <= IDLE;
            else case (state)
                IDLE: begin
                    if (load_mode) begin
                        state <= MAGIC;
                        cnt <= 2'b0;
                        len <= 32'b0;
                        off <= '0;
                        rvld <= WAIT;
                        sum <= '0;
                    end
                end

                MAGIC: begin
                    if (rx_valid) begin
                        case({rvld, rx_data})
                            {WAIT, R}: rvld <= R;   
                            {R, V}:    rvld <= V;
                            {V, L}:    rvld <= L;
                            {L, D}:    begin state <= LEN; rvld <= WAIT; end
                            default:   rvld <= (rx_data == R) ? R: WAIT;
                        endcase
                    end
                end

                LEN: begin
                    if (rx_valid) begin
                        len <= len_next;
                        cnt <= cnt + 1'b1;
                        if (cnt == 2'd3) begin
                            if (len_next > 65536 || len_next == 0 || len_next[1:0] != 0) begin  // trap, lol
                                state <= ERR;
                            end else begin
                            off <= '0;
                            state <= DATA;
                            cnt <= 2'd0;
                            end
                        end
                    end
                end

                DATA: begin
                    if (rx_valid) begin
                        word <= {rx_data, word[31:8]};
                        sum <= sum + rx_data;
                        off <= off + 1'b1;
                        if (off == len-1) state <= SUM;
                    end
                end

                SUM: begin
                    if (rx_valid) begin
                        if (cnt == 2'd3) begin
                            state <= DONE;
                            cnt <= 2'b0;
                        end
                        if (rx_data == sum[7:0]) begin
                            sum <= sum >> 8;
                            cnt <= cnt + 1'b1;
                        end
                        else begin
                            state <= ERR;
                        end
                    end
                end

                DONE: ;

                ERR: ;
                default: ;
            endcase
        end
    end
endmodule