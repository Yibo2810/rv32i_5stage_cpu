`timescale 1ns/1ps
// oled_seq + oled_spi together. The TB plays the SSD1331 (same receiver as oled_spi_tb)
// and watches the three power/reset pins.
//   make oled-seq-test                      (MS_CYCLES = 10: 1 "ms" = 10 clk in sim)
// Checks, against the Digilent OLEDrgb_DevInit() sequence:
//   - exactly 45 bytes, all D/C = 0: 39 config bytes + clear window (5) + AF
//   - PMODEN high before RES# pulse; RES# low >= 1 ms; RES# high before the first byte
//   - VCCEN stays 0 until the clear command is out, then waits >= 5 ms; AF >= 25 ms after VCCEN
//   - done >= 100 ms after AF; nothing sent after done; pins never drop afterwards
// Waits are checked in scaled ms (MS_CYCLES clk each), not real time, and are measured from
// the cycle oled_spi accepts a byte: oled_seq starts counting there, and on the board the
// ~34 clk the byte still spends on the wire is 1.4 us, nothing next to a ms.
module oled_seq_tb;
    localparam int MS_CYCLES = 10;
    localparam int HALF      = 2;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #20 clk = ~clk;

    logic       spi_valid, spi_busy;
    logic [7:0] spi_data;
    logic       pmoden, res_n, vccen, done;
    logic       cs_n, sclk, mosi, dc_o;

    localparam logic [7:0] EXPECT [0:44] = '{
        8'hFD, 8'h12, 8'hAE, 8'hA0, 8'h72, 8'hA1, 8'h00, 8'hA2, 8'h00, 8'hA4,
        8'hA8, 8'h3F, 8'hAD, 8'h8E, 8'hB0, 8'h0B, 8'hB1, 8'h31, 8'hB3, 8'hF0,
        8'h8A, 8'h64, 8'h8B, 8'h78, 8'h8C, 8'h64, 8'hBB, 8'h3A, 8'hBE, 8'h3E,
        8'h87, 8'h06, 8'h81, 8'h91, 8'h82, 8'h50, 8'h83, 8'h7D, 8'h2E,
        8'h25, 8'h00, 8'h00, 8'h5F, 8'h3F,
        8'hAF
    };
    localparam int N_CLEAR_END = 44;   // bytes [0..43] must be out before VCCEN
    localparam int N_TOTAL     = 45;

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        if (errors <= 20) $display("CHECK FAIL @cycle %0d: %s", cyc, msg);
    endtask

    // ---- cycle counter (all event times below are in clk cycles)
    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ---- SSD1331 receiver: shift mosi in on sclk rising edges while cs_n = 0
    logic [8:0]  got[$];               // {dc, byte}
    longint      acc_cyc[$];           // cycle when oled_spi accepted the byte (valid && !busy)
    logic [7:0]  rx;
    int unsigned nbits = 0;
    always @(posedge sclk) if (cs_n === 1'b0) begin
        rx = {rx[6:0], mosi};
        nbits++;
        if (nbits == 8) begin
            got.push_back({dc_o, rx});
            nbits = 0;
            if (res_n !== 1'b1)  fail("byte sent while RES# is not high");
            if (pmoden !== 1'b1) fail("byte sent while PMODEN is not high");
        end
    end
    always @(posedge cs_n) nbits = 0;
    always @(posedge clk) if (!rst && spi_valid === 1'b1 && spi_busy === 1'b0) acc_cyc.push_back(cyc);

    // ---- pin event log
    longint t_pmoden_up = -1, t_res_down = -1, t_res_up = -1, t_vcc_up = -1, t_done = -1;
    always @(posedge clk) if (!rst) begin
        if (pmoden === 1'b1 && t_pmoden_up < 0) t_pmoden_up = cyc;
        if (t_pmoden_up >= 0 && res_n === 1'b0 && t_res_down < 0) t_res_down = cyc;
        if (t_res_down >= 0 && res_n === 1'b1 && t_res_up < 0)  t_res_up = cyc;
        if (vccen === 1'b1 && t_vcc_up < 0) begin
            t_vcc_up = cyc;
            if (got.size() < N_CLEAR_END)
                fail($sformatf("VCCEN rose after only %0d bytes (config + clear = %0d must come first)", got.size(), N_CLEAR_END));
        end
        if (done === 1'b1 && t_done < 0) t_done = cyc;
        if (t_pmoden_up >= 0 && pmoden !== 1'b1) fail("PMODEN dropped after power-up");
        if (t_vcc_up >= 0 && vccen !== 1'b1)     fail("VCCEN dropped after it was raised");
        if (t_done >= 0 && done !== 1'b1)        fail("done dropped");
        if (t_done >= 0 && spi_valid === 1'b1)   fail("spi_valid asserted after done");
    end

    function automatic longint ms(input longint cycles);
        return cycles / MS_CYCLES;
    endfunction

    initial begin
        repeat (5) @(negedge clk);
        if (pmoden !== 1'b0 || vccen !== 1'b0 || done !== 1'b0)
            fail($sformatf("during reset: pmoden=%b vccen=%b done=%b, expected 0 0 0", pmoden, vccen, done));
        rst = 1'b0;

        while (done !== 1'b1 && cyc < 200_000) @(negedge clk);
        repeat (300 * MS_CYCLES) @(negedge clk);    // stay a while: nothing more may be sent

        // ---- bytes
        if (got.size() != N_TOTAL) fail($sformatf("received %0d bytes, expected %0d", got.size(), N_TOTAL));
        for (int i = 0; i < N_TOTAL && i < got.size(); i++) begin
            if (got[i][8] !== 1'b0) fail($sformatf("byte %0d (%02h): D/C = 1, init bytes are all commands", i, got[i][7:0]));
            if (got[i][7:0] !== EXPECT[i])
                fail($sformatf("byte %0d: got %02h, expected %02h", i, got[i][7:0], EXPECT[i]));
        end

        // ---- power / reset order and waits (scaled ms)
        if (t_pmoden_up < 0) fail("PMODEN never went high");
        if (t_res_down < 0 || t_res_up < 0) fail("no RES# low pulse after PMODEN");
        else begin
            if (ms(t_res_down - t_pmoden_up) < 20) fail($sformatf("RES# pulse %0d ms after PMODEN, expected >= 20", ms(t_res_down - t_pmoden_up)));
            if (ms(t_res_up - t_res_down) < 1)     fail($sformatf("RES# low %0d ms, expected >= 1", ms(t_res_up - t_res_down)));
            if (acc_cyc.size() > 0 && ms(acc_cyc[0] - t_res_up) < 2)
                fail($sformatf("first byte %0d ms after RES# release, expected >= 2", ms(acc_cyc[0] - t_res_up)));
        end
        if (t_vcc_up < 0) fail("VCCEN never went high");
        else if (acc_cyc.size() >= N_TOTAL) begin
            if (ms(t_vcc_up - acc_cyc[N_CLEAR_END-1]) < 5)
                fail($sformatf("VCCEN %0d ms after clear, expected >= 5", ms(t_vcc_up - acc_cyc[N_CLEAR_END-1])));
            if (ms(acc_cyc[N_TOTAL-1] - t_vcc_up) < 25)
                fail($sformatf("AF %0d ms after VCCEN, expected >= 25", ms(acc_cyc[N_TOTAL-1] - t_vcc_up)));
        end
        if (t_done < 0) fail("done never went high");
        else if (acc_cyc.size() >= N_TOTAL && ms(t_done - acc_cyc[N_TOTAL-1]) < 100)
            fail($sformatf("done %0d ms after AF, expected >= 100", ms(t_done - acc_cyc[N_TOTAL-1])));

        $display("SUMMARY bytes=%0d pmoden@%0d res_low@%0d res_high@%0d vccen@%0d done@%0d (cycles, 1 ms = %0d)",
                 got.size(), t_pmoden_up, t_res_down, t_res_up, t_vcc_up, t_done, MS_CYCLES);
        if (errors == 0) $display("OLED_SEQ PASS");
        else             $display("OLED_SEQ FAIL: %0d check(s)", errors);
        $finish;
    end

    oled_seq #(.MS_CYCLES(MS_CYCLES)) u_seq (
        .clk      (clk),
        .rst      (rst),
        .spi_valid(spi_valid),
        .spi_data (spi_data),
        .spi_busy (spi_busy),
        .pmoden   (pmoden),
        .res_n    (res_n),
        .vccen    (vccen),
        .done     (done)
    );

    oled_spi #(.HALF(HALF)) u_spi (
        .clk  (clk),
        .rst  (rst),
        .valid(spi_valid),
        .data (spi_data),
        .dc   (1'b0),
        .busy (spi_busy),
        .dc_o (dc_o),
        .mosi (mosi),
        .cs_n (cs_n),
        .sclk (sclk)
    );
endmodule
