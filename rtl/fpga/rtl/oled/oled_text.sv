`timescale 1ns/1ps
module oled_text
import peripherals::*;
 (
    input logic rst, clk,
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
    input logic [31:0] bus_err_addr,
    // ================================
    // from render, check which block(8x8)
    input logic [2:0] row,  // y[5:3] which block? 0-7 row
    input logic [3:0] col,  // x[6:3] 0-11 column

    output logic [7:0] ch,  // to font
    output logic [15:0] fg, // to render, color choice, frontground
    output logic [15:0] bg  // background color
);
    logic [7:0] text [128]; // {row, col}, 8-bit means one character, 2^7=128
    logic [15:0] row_fg[8]; // what color is on each row? 8 block, each block 16-bit

    function automatic logic [95:0] status_row(input logic halted, input logic pass);
        if (!halted)   return "RUN         ";
        else if (pass) return "PASS        ";
        else           return "FAIL        ";
    endfunction

    function automatic logic [95:0] panic_row(
        input logic [2:0] r,
        input logic halted, pass,
        input logic [3:0] trap_cause_q,
        input logic [31:0] trap_pc_q,
        input logic [31:0]tohost,
        input logic bus_err,
        input logic [31:0] bus_err_addr
    );
        case (r)
        3'd2: return {"CAUSE ", hex_ch(trap_cause_q), "     "};
        3'd3: return {"PC  ",   hex8_str(trap_pc_q)};
        3'd4: return {"TOH ",   hex8_str(tohost)};
        3'd5: return {"BUS ",   hex_ch({3'b0, bus_err}), "       "};
        3'd6: return {"ADR ",   hex8_str(bus_err_addr)};
        default: return "            ";
    endcase
    endfunction

    always_ff @( posedge clk ) begin
        if (rst) begin
            foreach (text[i]) text[i] <= '0;
            foreach (row_fg[i]) row_fg[i] <= '0;
        end
        else begin
            if (txt_wr) text[txt_idx] <= txt_data;
            if (col_wr) row_fg[col_idx] <= col_data;
        end
    end

    always_comb begin
        ch = 8'b00;
        fg = RGB_WHITE;
        bg = RGB_BLACK;
        if (row == 3'd0) begin
            ch = status_row(halted, pass)[8*(11-col) +:8];
            fg = RGB_BLACK;
            bg = !halted ? RGB_GREEN : (pass ? RGB_YELLOW : RGB_RED);
        end else if (!halted) begin                            // RUNNING
            ch = text[{row, col}];
            if (row_fg[row] != 16'h0) fg = row_fg[row];
        end else begin                                         // HALTED, panic
            ch = panic_row(row, halted, pass, trap_cause_q,
                            trap_pc_q, tohost, bus_err, bus_err_addr)[8*(11-col) +: 8];
            if (row == 3'd6 && bus_err) fg = RGB_RED;
        end
    end
endmodule