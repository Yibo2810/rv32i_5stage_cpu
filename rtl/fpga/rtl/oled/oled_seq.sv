`timescale 1ns/1ps
// This RTL basically accroding to Digilent Driver OLEDegb_DevInit
// We just writing it with RTL rather than C
module oled_seq 
#(
    parameter int MS_CYCLES = 25_000
) (
    input  logic rst, clk,
    output logic spi_valid,
    output logic spi_data,
    input  logic spi_busy,
    output logic pmoden, res_n, vccen,
    output logic done
);

    logic AW = $clog2(MS_CYCLES);
    logic [5:0] pc; // 56 microcode instructions based on the OLED datasheet
    logic in_wait;
    logic [7:0] ms_left;
    logic [AW-1:0] tick_cnt;
    logic [7:0] arg;
    logic [9:0] rom;
    logic [1:0] op;
    assign op = rom[9:8];
    assign arg = rom[7:0];

    // Send cmd
    function automatic logic [9:0] C(input logic [7:0] b);
        return {2'b00, b};
    endfunction
    // Setup pin {pmoden, res_n, vccen}
    function automatic logic [2:0] P(input logic [2:0] p);
        return {2'b01, 5'b0, p};
    endfunction
    // Wait ms
    function automatic logic [7:0] W(input logic [7:0] ms);
        return {2'b10, ms};
    endfunction
    // End
    function automatic logic [9:0] E();
        return {2'b11, 8'b0};
    endfunction

    localparam logic [7:0] CFG [0:43] = '{
        8'hFD, 8'h12,                       // Unlock
        8'hAE,                              // close display
        8'hA0, 8'h72,                       // RGB565 + direction
        8'hA1, 8'h00, 8'hA2, 8'h00, 8'hA4,
        8'hA8, 8'h3F, 8'hAD, 8'h8E, 8'hB0, 8'h0B, 8'hB1, 8'h31, 8'hB3, 8'hF0,
        8'h8A, 8'h64, 8'h8B, 8'h78, 8'h8C, 8'h64, 8'hBB, 8'h3A, 8'hBE, 8'h3E,
        8'h87, 8'h06, 8'h81, 8'h91, 8'h82, 8'h50, 8'h83, 8'h7D,
        8'h2E,                              // close rolling
        8'h25, 8'h00, 8'h00, 8'h5F, 8'h3F   // clear display: (0,0)-(95,63)
    };
    
    always_comb begin
        case (pc)
            6'd0:  rom = P(3'b110);
            6'd1:  rom = W(8'd20);
            6'd2:  rom = P(3'b100);
            6'd3:  rom = W(1);
            6'd4:  rom = P(3'b110);
            6'd5:  rom = W(2);
            6'd50: rom = W(5);
            6'd51: rom = P(3'b111);
            6'd52: rom = W(25);
            6'd53: rom = C(8'hAF);
            6'd54: rom = W(100);
            6'd55: rom = E();
            default: rom = (pc >= 6'd6 && pc <= 6'd49) ? C(CFG[pc - 6'd6]) : E();
        endcase
    end

    always_ff @( posedge clk ) begin
        if (rst) begin
            pc <= '0;
            pmoden <= 1'b0;
            res_n <= 1'b0;
            vccen <= 1'b0;
            done <= 1'b0;
            in_wait <= 1'b0;
            ms_left <= 8'b0;
            tick_cnt <= '0;
        end
        else begin
            case (op)
                2'b00: begin
                    {pmoden, res_n, vccen} <= arg[2:0];
                    pc <= pc + 1'b1;
                end

                2'b01: begin
                    spi_valid = 1'b1;
                    spi_data = arg;
                    if (!spi_busy) pc <= pc + 1'b1;
                end
                default: 
            endcase
        end
    end
endmodule