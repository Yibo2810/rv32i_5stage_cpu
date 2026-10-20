`timescale 1ns/1ps
// S2 check: oled_ctrl (seq -> fill handover) into the SSD1331 model.
//   make oled-ctrl-test                     (MS_CYCLES = 10, HALF = 2)
// Checks:
//   - the 45 init bytes (D/C = 0) come first, unchanged
//   - then N_FRAMES frames, each: 15 00 5F 75 00 3F (D/C = 0) + 12288 bytes (D/C = 1) = F8 00 ...
//   - pins after init: PMODEN = RES# = VCCEN = 1; model saw display on, no unknown command
//   - every pixel of the model's GDDRAM is F800 after the frames
// Writes sim/build/oled_ctrl_vcs/frame.ppm (open it: should be solid red).
module oled_ctrl_tb;
    localparam int MS_CYCLES = 10;
    localparam int HALF      = 2;
    localparam int N_FRAMES  = 2;
    localparam int N_INIT    = 45;
    localparam int FRAME_LEN = 6 + 96 * 64 * 2;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #20 clk = ~clk;

    logic oled_cs_n, oled_mosi, oled_sclk, oled_dc, oled_res_n, oled_vccen, oled_pmoden;

    localparam logic [7:0] INIT [0:N_INIT-1] = '{
        8'hFD, 8'h12, 8'hAE, 8'hA0, 8'h72, 8'hA1, 8'h00, 8'hA2, 8'h00, 8'hA4,
        8'hA8, 8'h3F, 8'hAD, 8'h8E, 8'hB0, 8'h0B, 8'hB1, 8'h31, 8'hB3, 8'hF0,
        8'h8A, 8'h64, 8'h8B, 8'h78, 8'h8C, 8'h64, 8'hBB, 8'h3A, 8'hBE, 8'h3E,
        8'h87, 8'h06, 8'h81, 8'h91, 8'h82, 8'h50, 8'h83, 8'h7D, 8'h2E,
        8'h25, 8'h00, 8'h00, 8'h5F, 8'h3F,
        8'hAF
    };
    localparam logic [7:0] WIN [0:5] = '{8'h15, 8'h00, 8'h5F, 8'h75, 8'h00, 8'h3F};

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        if (errors <= 20) $display("CHECK FAIL: %s", msg);
    endtask

    task automatic expect_byte(input int i, input logic [7:0] b, input bit d, input string what);
        if (i >= u_oled.bytes.size()) return;
        if (u_oled.bytes[i] !== b || u_oled.dcs[i] !== d)
            fail($sformatf("byte %0d (%s): got dc=%b %02h, expected dc=%b %02h",
                           i, what, u_oled.dcs[i], u_oled.bytes[i], d, b));
    endtask

    initial begin
        int unsigned guard = 0;
        int unsigned want  = N_INIT + N_FRAMES * FRAME_LEN;
        int unsigned not_red = 0;
        int          base;

        repeat (5) @(negedge clk);
        rst = 1'b0;
        while (u_oled.bytes.size() < want && guard < 3_000_000) begin
            @(negedge clk);
            guard++;
        end
        if (u_oled.bytes.size() < want)
            fail($sformatf("only %0d bytes after %0d cycles, expected at least %0d", u_oled.bytes.size(), guard, want));

        for (int i = 0; i < N_INIT; i++) expect_byte(i, INIT[i], 1'b0, "init");
        for (int f = 0; f < N_FRAMES; f++) begin
            base = N_INIT + f * FRAME_LEN;
            for (int i = 0; i < 6; i++) expect_byte(base + i, WIN[i], 1'b0, $sformatf("frame %0d window", f));
            for (int i = 0; i < FRAME_LEN - 6; i++) begin
                expect_byte(base + 6 + i, i[0] ? 8'h00 : 8'hF8, 1'b1, $sformatf("frame %0d pixel byte %0d", f, i));
                if (errors > 20) break;
            end
        end

        if (oled_pmoden !== 1'b1 || oled_res_n !== 1'b1 || oled_vccen !== 1'b1)
            fail($sformatf("pins after init: pmoden=%b res_n=%b vccen=%b, expected 1 1 1", oled_pmoden, oled_res_n, oled_vccen));
        if (!u_oled.display_on) fail("model never saw display on (AF)");
        if (u_oled.bad_cmds != 0) fail($sformatf("model saw %0d unknown command byte(s)", u_oled.bad_cmds));
        for (int r = 0; r < 64; r++)
            for (int c = 0; c < 96; c++)
                if (u_oled.fb[r][c] !== 16'hF800) not_red++;
        if (not_red != 0) fail($sformatf("%0d of 6144 pixels are not F800", not_red));

        u_oled.dump_ppm("sim/build/oled_ctrl_vcs/frame.ppm");
        $display("SUMMARY bytes=%0d pixels_written=%0d display_on=%0d not_red=%0d cycles=%0d",
                 u_oled.bytes.size(), u_oled.pixels, u_oled.display_on, not_red, guard);
        if (errors == 0) $display("OLED_CTRL PASS");
        else             $display("OLED_CTRL FAIL: %0d check(s)", errors);
        $finish;
    end

    oled_ctrl #(.MS_CYCLES(MS_CYCLES), .HALF(HALF)) dut (
        .clk        (clk),
        .rst        (rst),
        .oled_cs_n  (oled_cs_n),
        .oled_mosi  (oled_mosi),
        .oled_sclk  (oled_sclk),
        .oled_dc    (oled_dc),
        .oled_res_n (oled_res_n),
        .oled_vccen (oled_vccen),
        .oled_pmoden(oled_pmoden)
    );

    ssd1331_model u_oled (
        .cs_n  (oled_cs_n),
        .sclk  (oled_sclk),
        .mosi  (oled_mosi),
        .dc    (oled_dc),
        .res_n (oled_res_n),
        .vccen (oled_vccen),
        .pmoden(oled_pmoden)
    );
endmodule
