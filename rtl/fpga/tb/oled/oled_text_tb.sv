`timescale 1ns/1ps
// Unit test for oled_text: drive (row, col) directly and read back ch / fg / bg.
//   make oled-text-test
// Cases: reset -> blank cells; CPU writes chars and a row colour while running;
// row 0 status bar for RUN / PASS / FAIL; panic rows 2..6 after halt (exact 12-char strings);
// ADR row red when bus_err; columns 12..15 written by the CPU are never shown (renderer
// only asks 0..11, checked here by reading 0..11 only).
module oled_text_tb;
    import peripherals::*;

    logic        clk = 1'b0;
    logic        rst = 1'b1;
    always #20 clk = ~clk;

    logic        txt_wr = 1'b0, col_wr = 1'b0;
    logic [6:0]  txt_idx = '0;
    logic [7:0]  txt_data = '0;
    logic [2:0]  col_idx = '0;
    logic [15:0] col_data = '0;
    logic        halted = 1'b0, pass = 1'b0, bus_err = 1'b0;
    logic [3:0]  trap_cause_q = '0;
    logic [31:0] trap_pc_q = '0, tohost = '0, bus_err_addr = '0;
    logic [2:0]  row = '0;
    logic [3:0]  col = '0;
    logic [7:0]  ch;
    logic [15:0] fg, bg;

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        if (errors <= 25) $display("CHECK FAIL: %s", msg);
    endtask

    task automatic put(input int r, input int c, input byte b);
        @(negedge clk);
        txt_wr = 1'b1; txt_idx = {3'(r), 4'(c)}; txt_data = b;
        @(negedge clk);
        txt_wr = 1'b0;
    endtask

    task automatic set_color(input int r, input logic [15:0] rgb);
        @(negedge clk);
        col_wr = 1'b1; col_idx = 3'(r); col_data = rgb;
        @(negedge clk);
        col_wr = 1'b0;
    endtask

    // Read one 12-char row as a string (NUL shown as '.') and check its colours.
    task automatic read_row(input int r, output string s);
        s = "";
        for (int c = 0; c < 12; c++) begin
            row = 3'(r); col = 4'(c);
            #1;
            s = {s, (ch == 8'h00) ? "." : string'(ch)};
        end
    endtask

    task automatic expect_row(input int r, input string want, input logic [15:0] want_fg,
                              input logic [15:0] want_bg, input string what);
        string got;
        logic [15:0] f, b;
        row = 3'(r); col = 4'd0; #1;
        f = fg; b = bg;
        read_row(r, got);
        #1;
        if (got != want) fail($sformatf("%s row %0d: got \"%s\", want \"%s\"", what, r, got, want));
        if (f !== want_fg || b !== want_bg)
            fail($sformatf("%s row %0d: fg/bg %04h/%04h, want %04h/%04h", what, r, f, b, want_fg, want_bg));
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // T1 reset: running, rows 1..7 blank white-on-black, row 0 green RUN
        expect_row(0, "RUN         ", RGB_BLACK, RGB_GREEN, "T1");
        for (int r = 1; r < 8; r++) expect_row(r, "............", RGB_WHITE, RGB_BLACK, "T1");

        // T2 CPU text: "Hi" at row 2 col 5, full row 7, colour on row 2; col 12 write not shown
        put(2, 5, "H"); put(2, 6, "i"); put(2, 12, "X");
        for (int c = 0; c < 12; c++) put(7, c, 8'("A" + c));
        set_color(2, RGB_YELLOW);
        expect_row(2, ".....Hi.....", RGB_YELLOW, RGB_BLACK, "T2");
        expect_row(7, "ABCDEFGHIJKL", RGB_WHITE, RGB_BLACK, "T2");
        expect_row(1, "............", RGB_WHITE, RGB_BLACK, "T2");

        // T3 halt + PASS: status yellow, panic rows replace CPU text
        trap_cause_q = 4'h3; trap_pc_q = 32'h8000_0040; tohost = 32'h1;
        bus_err = 1'b0; bus_err_addr = 32'h0;
        halted = 1'b1; pass = 1'b1;
        expect_row(0, "PASS        ", RGB_BLACK, RGB_YELLOW, "T3");
        expect_row(1, "            ", RGB_WHITE, RGB_BLACK, "T3");
        expect_row(2, "CAUSE 3     ", RGB_WHITE, RGB_BLACK, "T3");
        expect_row(3, "PC  80000040", RGB_WHITE, RGB_BLACK, "T3");
        expect_row(4, "TOH 00000001", RGB_WHITE, RGB_BLACK, "T3");
        expect_row(5, "BUS 0       ", RGB_WHITE, RGB_BLACK, "T3");
        expect_row(6, "ADR 00000000", RGB_WHITE, RGB_BLACK, "T3");
        expect_row(7, "            ", RGB_WHITE, RGB_BLACK, "T3");

        // T4 halt + FAIL with bus error: status red, ADR row red, hex digits a-f lowercase
        pass = 1'b0; trap_cause_q = 4'h2; trap_pc_q = 32'h8000_00ac;
        tohost = 32'h0; bus_err = 1'b1; bus_err_addr = 32'h2000_000f;
        expect_row(0, "FAIL        ", RGB_BLACK, RGB_RED, "T4");
        expect_row(2, "CAUSE 2     ", RGB_WHITE, RGB_BLACK, "T4");
        expect_row(3, "PC  800000ac", RGB_WHITE, RGB_BLACK, "T4");
        expect_row(5, "BUS 1       ", RGB_WHITE, RGB_BLACK, "T4");
        expect_row(6, "ADR 2000000f", RGB_RED,   RGB_BLACK, "T4");

        $display("SUMMARY errors=%0d", errors);
        if (errors == 0) $display("OLED_TEXT PASS");
        else             $display("OLED_TEXT FAIL");
        $finish;
    end

    oled_text dut (
        .clk(clk), .rst(rst),
        .txt_wr(txt_wr), .txt_idx(txt_idx), .txt_data(txt_data),
        .col_wr(col_wr), .col_idx(col_idx), .col_data(col_data),
        .halted(halted), .pass(pass), .trap_cause_q(trap_cause_q), .trap_pc_q(trap_pc_q),
        .tohost(tohost), .bus_err(bus_err), .bus_err_addr(bus_err_addr),
        .row(row), .col(col), .ch(ch), .fg(fg), .bg(bg)
    );
endmodule
