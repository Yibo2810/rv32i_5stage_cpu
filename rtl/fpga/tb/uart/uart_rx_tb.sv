`timescale 1ns/1ps
// Unit test for uart_rx. The sender is behavioral and runs on real time (#ns), not on
// the DUT clock: every frame starts at a random sub-clock phase, and the bit time can be
// off by a few percent. That is what the FTDI chip looks like from the FPGA: an unrelated
// clock, close to but not exactly CLKS_PER_BIT * 40 ns per bit.
//   make uart-rx-test                       (builds and runs CPB = 12, then the board value 217;
//                                            -pvalue is a compile option, so two simv)
// CPB is deliberately not a power of two: a bit counter that relies on natural wrap-around
// instead of being cleared at CLKS_PER_BIT-1 passes at 8/16 and fails on the board (217).
// Checks: every byte and frame_err exactly as sent, rx_valid exactly 1 cycle per frame,
// back-to-back frames, +-3 % baud error, short glitch on the idle line ignored,
// stop bit = 0 reported as frame_err (byte still delivered), no X on outputs after reset.
// Metastability itself cannot be simulated; the 2-FF synchronizer is checked by review.
module uart_rx_tb;
    parameter int CPB = 12;
    localparam realtime CLK_NS = 40.0;
    localparam realtime BIT_NS = CPB * CLK_NS;

    logic       clk = 1'b0;
    logic       rst = 1'b1;
    logic       rx  = 1'b1;
    logic       rx_valid, frame_err;
    logic [7:0] rx_data;
    always #(CLK_NS / 2) clk = ~clk;

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        if (errors <= 20) $display("CHECK FAIL @%0t: %s", $time, msg);
    endtask

    // ---- expected vs received {frame_err, data}
    logic [8:0] sent[$];
    logic [8:0] got[$];
    int unsigned valid_run = 0;

    always @(posedge clk) if (!rst) begin
        if (rx_valid === 1'b1) begin
            if (valid_run == 0) got.push_back({frame_err, rx_data});
            valid_run++;
            if (valid_run == 2) fail("rx_valid high for more than 1 cycle");
        end else begin
            valid_run = 0;
        end
        if ($isunknown({rx_valid, frame_err}) || (rx_valid === 1'b1 && $isunknown(rx_data)))
            fail("X/Z on rx_valid/frame_err/rx_data");
    end

    // ---- sender: one 8N1 frame on real time
    task automatic send(input logic [7:0] b, input real err = 0.0, input logic stop = 1'b1,
                        input bit gap = 1'b1);
        realtime bit_t = BIT_NS * (1.0 + err);
        if (gap) #($urandom_range(0, 39999) * 1ps + 2 * BIT_NS);   // idle, random phase vs clk
        rx = 1'b0;
        #(bit_t);
        for (int i = 0; i < 8; i++) begin
            rx = b[i];
            #(bit_t);
        end
        rx = stop;
        #(bit_t);
        rx = 1'b1;
        sent.push_back({!stop, b});
    endtask

    task automatic settle();
        #(3 * BIT_NS);
    endtask

    initial begin
        real e;
        #(5 * CLK_NS);
        rst = 1'b0;
        #(4 * BIT_NS);
        if (got.size() != 0) fail("byte received out of reset with an idle line");

        // single bytes, nominal baud: 55/AA alternate every bit
        send(8'h00); send(8'hFF); send(8'h55); send(8'hAA); send(8'h41); send(8'h80); send(8'h01);
        settle();

        // baud error: sender 3 % slow and 3 % fast
        for (int i = 0; i < 6; i++) send(8'(8'h3C + 37 * i), 0.03);
        for (int i = 0; i < 6; i++) send(8'(8'hC3 + 29 * i), -0.03);
        settle();

        // back-to-back: next start bit right after the stop bit, at all three rates
        for (int k = 0; k < 3; k++) begin
            e = (k == 0) ? 0.0 : (k == 1) ? 0.03 : -0.03;
            send(8'hA5, e);
            for (int i = 0; i < 15; i++) send(8'(i * 17 + 3), e, 1'b1, 1'b0);
            settle();
        end

        // glitch on the idle line, shorter than half a bit: must be ignored
        #(BIT_NS);
        rx = 1'b0;
        #(0.3 * BIT_NS);
        rx = 1'b1;
        settle();

        // stop bit = 0: byte delivered with frame_err, then a normal byte still works
        send(8'h5A, 0.0, 1'b0);
        send(8'h33);
        settle();

        if (got.size() != sent.size())
            fail($sformatf("received %0d frames, sent %0d", got.size(), sent.size()));
        for (int i = 0; i < sent.size() && i < got.size(); i++)
            if (got[i] !== sent[i])
                fail($sformatf("frame %0d: got data=%02h frame_err=%b, sent data=%02h stop_bad=%b",
                               i, got[i][7:0], got[i][8], sent[i][7:0], sent[i][8]));

        $display("SUMMARY CPB=%0d sent=%0d received=%0d errors=%0d", CPB, sent.size(), got.size(), errors);
        if (errors == 0) $display("UART_RX PASS");
        else             $display("UART_RX FAIL");
        $finish;
    end

    initial begin
        #(2000 * BIT_NS);
        $display("UART_RX FAIL: global timeout");
        $finish;
    end

    uart_rx #(.CLKS_PER_BIT(CPB)) dut (
        .clk      (clk),
        .rst      (rst),
        .rx       (rx),
        .rx_valid (rx_valid),
        .rx_data  (rx_data),
        .frame_err(frame_err)
    );
endmodule
