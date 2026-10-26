`timescale 1ns/1ps
// oled_render (+ oled_text + oled_font) -> oled_spi -> SSD1331 model, whole frames checked
// pixel by pixel against a reference picture built here from literal strings.
//   make oled-render-test            -> also writes sim/build/oled_render_vcs/frame_<case>.ppm
// Cases: RUN with CPU text + a row colour; halted PASS; halted FAIL with bus_err.
// Each case changes the inputs, lets the frame in flight finish, then checks the next full
// frame (a change only shows once the scan reaches it).
// The reference glyphs are read from oled_font itself (checked separately by printing them);
// what this test checks is the renderer: scan order, row/col/gx/gy split, hi/lo byte order,
// D/C, window bytes, and oled_text's row sources and colours.
module oled_render_tb;
    import peripherals::*;
    localparam int W = 96, H = 64;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #20 clk = ~clk;

    logic        start = 1'b0;
    logic        spi_busy, spi_valid, dc;
    logic [7:0]  spi_data;
    logic        txt_wr = 1'b0, col_wr = 1'b0;
    logic [6:0]  txt_idx = '0;
    logic [7:0]  txt_data = '0;
    logic [2:0]  col_idx = '0;
    logic [15:0] col_data = '0;
    logic        halted = 1'b0, pass = 1'b0, bus_err = 1'b0;
    logic [3:0]  trap_cause_q = '0;
    logic [31:0] trap_pc_q = '0, tohost = '0, bus_err_addr = '0;
    logic        cs_n, sclk, mosi, dc_o;

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        if (errors <= 25) $display("CHECK FAIL: %s", msg);
    endtask

    // ---- reference glyph table, read out of oled_font
    logic [7:0] f_ch = '0;
    logic [2:0] f_gy = '0;
    logic [7:0] f_bits;
    logic [7:0] glyph [128][8];
    oled_font u_ref_font (.ch(f_ch), .gy(f_gy), .bits(f_bits));

    // ---- expected screen: 8 rows of 12 chars + colours
    string       exp_txt [8];
    logic [15:0] exp_fg  [8];
    logic [15:0] exp_bg  [8];

    function automatic logic [7:0] code_at(input string s, input int c);
        return (c < s.len()) ? s[c] : 8'h00;
    endfunction

    task automatic check_frame(input string name);
        int bad = 0, first_r = -1, first_c = -1;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) begin
                int r = y / 8, c = x / 8;
                logic [7:0] ch = code_at(exp_txt[r], c);
                logic [15:0] want = glyph[ch & 8'h7f][y % 8][x % 8] ? exp_fg[r] : exp_bg[r];
                if (u_oled.fb[y][x] !== want) begin
                    bad++;
                    if (first_r < 0) begin first_r = r; first_c = c; end
                    if (bad <= 3) fail($sformatf("%s pixel (%0d,%0d) cell r%0d c%0d '%s': got %04h, want %04h",
                                                 name, x, y, r, c, string'(ch), u_oled.fb[y][x], want));
                end
            end
        if (bad != 0) fail($sformatf("%s: %0d / 6144 pixels wrong (first in cell r%0d c%0d)", name, bad, first_r, first_c));
        else $display("FRAME %s OK", name);
        u_oled.dump_ppm($sformatf("sim/build/oled_render_vcs/frame_%s.ppm", name));
    endtask

    // let the frame in flight finish, then render one full frame with the new inputs
    task automatic next_full_frame();
        repeat (2) begin
            wait (dut.state == 1'b1);
            wait (dut.state == 1'b0);
        end
        repeat (50) @(posedge clk);
    endtask

    task automatic put(input int r, input int c, input logic [7:0] b);
        @(negedge clk); txt_wr = 1'b1; txt_idx = {3'(r), 4'(c)}; txt_data = b;
        @(negedge clk); txt_wr = 1'b0;
    endtask
    task automatic puts(input int r, input string s);
        for (int c = 0; c < s.len(); c++) put(r, c, s[c]);
    endtask
    task automatic set_color(input int r, input logic [15:0] rgb);
        @(negedge clk); col_wr = 1'b1; col_idx = 3'(r); col_data = rgb;
        @(negedge clk); col_wr = 1'b0;
    endtask

    int unsigned win_errs = 0, dc_errs = 0;
    // window bytes must be exactly 15 00 5F 75 00 3F with D/C = 0 before every frame
    logic [7:0] WIN_BYTES [6] = '{8'h15, 8'h00, 8'h5F, 8'h75, 8'h00, 8'h3F};
    int unsigned seen = 0;
    always @(posedge clk) if (!rst && spi_valid && !spi_busy) begin
        if (dut.state == 1'b0) begin
            if (dc !== 1'b0 || spi_data !== WIN_BYTES[dut.cnt]) win_errs++;
        end else if (dc !== 1'b1) dc_errs++;
    end

    initial begin
        for (int ch = 0; ch < 128; ch++)
            for (int gy = 0; gy < 8; gy++) begin
                f_ch = 8'(ch); f_gy = 3'(gy); #1;
                glyph[ch][gy] = f_bits;
            end

        repeat (5) @(negedge clk);
        rst = 1'b0;

        // ---- case 1: RUN, CPU text, row 2 yellow, a write to column 12 must not show
        puts(1, "Hello RV32I");
        puts(2, "THANK YOU \003");
        puts(7, "ABCDEFGHIJKL");
        put(2, 12, "X");
        set_color(2, RGB_YELLOW);
        @(negedge clk); start = 1'b1;
        exp_txt = '{"RUN", "Hello RV32I", "THANK YOU \003", "", "", "", "", "ABCDEFGHIJKL"};
        foreach (exp_fg[r]) begin exp_fg[r] = RGB_WHITE; exp_bg[r] = RGB_BLACK; end
        exp_fg[0] = RGB_BLACK; exp_bg[0] = RGB_GREEN; exp_fg[2] = RGB_YELLOW;
        exp_txt[0] = "RUN         ";
        next_full_frame();
        check_frame("run");

        // ---- case 2: halted PASS
        trap_cause_q = 4'h3; trap_pc_q = 32'h8000_0040; tohost = 32'h1; bus_err = 1'b0; bus_err_addr = '0;
        pass = 1'b1; halted = 1'b1;
        exp_txt = '{"PASS        ", "            ", "CAUSE 3     ", "PC  80000040", "TOH 00000001",
                    "BUS 0       ", "ADR 00000000", "            "};
        foreach (exp_fg[r]) begin exp_fg[r] = RGB_WHITE; exp_bg[r] = RGB_BLACK; end
        exp_fg[0] = RGB_BLACK; exp_bg[0] = RGB_YELLOW;
        next_full_frame();
        check_frame("pass");

        // ---- case 3: halted FAIL, bus error -> ADR row red
        pass = 1'b0; trap_cause_q = 4'h2; trap_pc_q = 32'h8000_00ac; tohost = '0;
        bus_err = 1'b1; bus_err_addr = 32'h2000_000f;
        exp_txt = '{"FAIL        ", "            ", "CAUSE 2     ", "PC  800000ac", "TOH 00000000",
                    "BUS 1       ", "ADR 2000000f", "            "};
        foreach (exp_fg[r]) begin exp_fg[r] = RGB_WHITE; exp_bg[r] = RGB_BLACK; end
        exp_fg[0] = RGB_BLACK; exp_bg[0] = RGB_RED; exp_fg[6] = RGB_RED;
        next_full_frame();
        check_frame("fail");

        if (win_errs) fail($sformatf("%0d window bytes wrong (want 15 00 5F 75 00 3F, D/C=0)", win_errs));
        if (dc_errs)  fail($sformatf("%0d pixel bytes sent with D/C=0", dc_errs));
        if (u_oled.bad_cmds) fail($sformatf("model saw %0d unknown command bytes", u_oled.bad_cmds));
        $display("SUMMARY frames_checked=3 pixels_written=%0d errors=%0d", u_oled.pixels, errors);
        if (errors == 0) $display("OLED_RENDER PASS");
        else             $display("OLED_RENDER FAIL");
        $finish;
    end

    initial begin
        #200ms;
        $display("OLED_RENDER FAIL: global timeout");
        $finish;
    end

    oled_render dut (
        .clk(clk), .rst(rst), .start(start), .spi_busy(spi_busy), .spi_valid(spi_valid),
        .spi_data(spi_data), .dc(dc),
        .txt_wr(txt_wr), .txt_idx(txt_idx), .txt_data(txt_data),
        .col_wr(col_wr), .col_idx(col_idx), .col_data(col_data),
        .halted(halted), .pass(pass), .trap_cause_q(trap_cause_q), .trap_pc_q(trap_pc_q),
        .tohost(tohost), .bus_err(bus_err), .bus_err_addr(bus_err_addr)
    );

    oled_spi #(.HALF(2)) u_spi (
        .clk(clk), .rst(rst), .valid(spi_valid), .data(spi_data), .dc(dc),
        .busy(spi_busy), .dc_o(dc_o), .mosi(mosi), .cs_n(cs_n), .sclk(sclk)
    );

    ssd1331_model u_oled (
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .dc(dc_o),
        .res_n(1'b1), .vccen(1'b1), .pmoden(1'b1)
    );
endmodule
