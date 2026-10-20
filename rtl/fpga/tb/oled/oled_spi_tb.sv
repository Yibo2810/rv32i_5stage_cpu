`timescale 1ns/1ps
// Unit test for oled_spi. The TB plays the SSD1331: while cs_n = 0 it shifts mosi in
// on every sclk rising edge (MSB first) and latches dc_o with each completed byte.
//   make oled-spi-test                      (HALF = 2, clk 25 MHz -> sclk 6.25 MHz)
// Checks: bytes and D/C received exactly, cs_n framing (8 bits per cs_n low),
// mode 3 (sclk high when cs_n falls), SSD1331 Table 21 timing, back-to-back bytes.
module oled_spi_tb;
    localparam int HALF = 2;

    // SSD1331 datasheet Rev 1.2, Table 21 (serial interface), in ns
    localparam realtime T_CLKL = 75, T_CLKH = 75, T_CSS = 75, T_CSH = 60;

    logic       clk = 1'b0;
    logic       rst = 1'b1;
    logic       valid = 1'b0;
    logic [7:0] data  = 8'h00;
    logic       dc    = 1'b0;
    logic       busy, dc_o, mosi, cs_n, sclk;
    always #20 clk = ~clk;

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        if (errors <= 20) $display("CHECK FAIL @%0t: %s", $time, msg);
    endtask

    // ---- SSD1331 side: receiver + timing monitor
    logic [8:0]  got[$];            // {dc, byte}
    logic [7:0]  rx;
    int unsigned nbits = 0;
    logic        dc_first;
    realtime     t_cs_fall, t_rise, t_fall, t_last_rise;
    bit          first_rise;
    bit          in_frame = 1'b0;   // set by a real cs_n falling edge (ignores the X->1 at reset)

    always @(negedge cs_n) begin
        t_cs_fall  = $realtime;
        first_rise = 1'b1;
        in_frame   = 1'b1;
        if (sclk !== 1'b1) fail("mode 3: sclk must be high when cs_n falls");
    end

    always @(posedge cs_n) begin
        if (in_frame) begin
            if (nbits != 0) fail($sformatf("cs_n rose after %0d bits (expected 8)", nbits));
            if (!first_rise && $realtime - t_last_rise < T_CSH)
                fail($sformatf("tCSH %0.0f ns < %0.0f", $realtime - t_last_rise, T_CSH));
        end
        in_frame = 1'b0;
        nbits    = 0;
    end

    always @(posedge sclk) begin
        t_rise = $realtime;
        if (cs_n === 1'b0) begin
            if (first_rise) begin
                if (t_rise - t_cs_fall < T_CSS) fail($sformatf("tCSS %0.0f ns < %0.0f", t_rise - t_cs_fall, T_CSS));
                first_rise = 1'b0;
            end else if (t_rise - t_fall < T_CLKL) begin
                fail($sformatf("sclk low %0.0f ns < %0.0f", t_rise - t_fall, T_CLKL));
            end
            if (mosi !== 1'b0 && mosi !== 1'b1) fail("mosi is X/Z at an sclk rising edge");
            if (nbits == 0) dc_first = dc_o;
            else if (dc_o !== dc_first) fail("dc_o changed in the middle of a byte");
            rx = {rx[6:0], mosi};
            nbits++;
            t_last_rise = t_rise;
            if (nbits == 8) begin
                got.push_back({dc_o, rx});
                nbits = 0;
            end
        end
    end

    always @(negedge sclk) begin
        if (cs_n === 1'b0 && $realtime - t_rise < T_CLKH)
            fail($sformatf("sclk high %0.0f ns < %0.0f", $realtime - t_rise, T_CLKH));
        t_fall = $realtime;
    end

    // ---- Host side
    logic [8:0] sent[$];

    // Hold valid until the byte is accepted (valid && !busy at a rising edge).
    task automatic send(input logic [7:0] d, input logic c);
        valid = 1'b1;
        data  = d;
        dc    = c;
        do @(posedge clk); while (busy);
        sent.push_back({c, d});
        @(negedge clk);
        valid = 1'b0;
        data  = 8'hxx;
        dc    = 1'bx;
    endtask

    task automatic wait_idle();
        int unsigned guard = 0;
        do begin
            @(negedge clk);
            guard++;
        end while ((busy || !cs_n) && guard < 10_000);
        if (guard >= 10_000) fail("busy/cs_n never returned idle");
        repeat (4) @(negedge clk);
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);
        if (cs_n !== 1'b1 || sclk !== 1'b1 || busy !== 1'b0)
            fail($sformatf("after reset: cs_n=%b sclk=%b busy=%b, expected 1 1 0", cs_n, sclk, busy));

        // Single bytes with gaps: bit order and dc
        send(8'hA5, 1'b0); wait_idle();
        send(8'h00, 1'b1); wait_idle();
        send(8'hFF, 1'b0); wait_idle();
        send(8'h80, 1'b1); wait_idle();
        send(8'h01, 1'b0); wait_idle();

        // Back-to-back: valid held, next byte offered right after acceptance
        for (int i = 0; i < 16; i++) begin
            valid = 1'b1;
            data  = 8'(i * 37 + 5);
            dc    = i[0];
            do @(posedge clk); while (busy);
            sent.push_back({dc, data});
            @(negedge clk);
        end
        valid = 1'b0;
        wait_idle();

        if (got.size() != sent.size())
            fail($sformatf("received %0d bytes, sent %0d", got.size(), sent.size()));
        for (int i = 0; i < sent.size() && i < got.size(); i++)
            if (got[i] !== sent[i])
                fail($sformatf("byte %0d: got dc=%b %02h, sent dc=%b %02h",
                               i, got[i][8], got[i][7:0], sent[i][8], sent[i][7:0]));

        $display("SUMMARY sent=%0d received=%0d errors=%0d", sent.size(), got.size(), errors);
        if (errors == 0) $display("OLED_SPI PASS");
        else             $display("OLED_SPI FAIL");
        $finish;
    end

    initial begin
        #2ms;
        $display("OLED_SPI FAIL: global timeout");
        $finish;
    end

    oled_spi #(.HALF(HALF)) dut (
        .clk  (clk),
        .rst  (rst),
        .valid(valid),
        .data (data),
        .dc   (dc),
        .busy (busy),
        .dc_o (dc_o),
        .mosi (mosi),
        .cs_n (cs_n),
        .sclk (sclk)
    );
endmodule
