`timescale 1ns/1ps
// Unit test for uart_tx against the independent uart_rx_model.
//   make uart-tx-test                      (CLKS_PER_BIT = 8)
// Checks: idle high after reset, every byte decoded (LSB first, full stop bit),
// tx_busy lasts 10 bit times, back-to-back bytes, tx_valid while busy ignored.
module uart_tx_tb;
    localparam int CPB = 8;

    logic       clk = 1'b0;
    logic       rst = 1'b1;
    logic       tx_valid = 1'b0;
    logic [7:0] tx_data  = 8'h00;
    logic       tx_busy;
    logic       tx;
    always #20 clk = ~clk;

    byte unsigned expected[$];
    int unsigned  errors = 0;

    task automatic fail(input string msg);
        errors++;
        $display("CHECK FAIL: %s", msg);
    endtask

    // Drive one byte for one cycle, then measure how long tx_busy stays high.
    task automatic send(input byte unsigned d, input bit check_len = 1'b1);
        int unsigned n = 0;
        while (tx_busy) @(negedge clk);
        tx_valid = 1'b1;
        tx_data  = d;
        @(negedge clk);
        tx_valid = 1'b0;
        tx_data  = 8'hxx;                 // data is only valid with tx_valid
        expected.push_back(d);
        while (tx_busy) begin
            n++;
            @(negedge clk);
        end
        if (check_len && !(n inside {[10*CPB : 10*CPB+1]}))
            fail($sformatf("byte %02h: tx_busy high %0d cycles, expected %0d (10 bits x %0d)",
                           d, n, 10*CPB, CPB));
    endtask

    initial begin
        // 1. reset: tx must be 1, nothing received
        repeat (3) @(negedge clk);
        if (tx !== 1'b1) fail($sformatf("tx = %b during reset, must be 1", tx));
        rst = 1'b0;
        repeat (4*CPB) @(negedge clk);
        if (tx !== 1'b1 || tx_busy !== 1'b0) fail("not idle (tx=1, busy=0) after reset");

        // 2. single bytes: alternating bits, all 0, all 1, MSB only, LSB only, ASCII
        send(8'h55); send(8'h00); send(8'hff); send(8'h80); send(8'h01); send(8'h41);

        // 3. back to back: next tx_valid in the first idle cycle
        send(8'ha5); send(8'h5a);

        // 4. tx_valid while busy must be ignored (no restart, no extra byte)
        while (tx_busy) @(negedge clk);
        tx_valid = 1'b1; tx_data = 8'h3c;
        @(negedge clk);
        tx_valid = 1'b0;
        expected.push_back(8'h3c);
        repeat (3*CPB) @(negedge clk);    // mid-frame
        tx_valid = 1'b1; tx_data = 8'hee; // must not appear
        @(negedge clk);
        tx_valid = 1'b0; tx_data = 8'hxx;
        while (tx_busy) @(negedge clk);

        // 5. a line, echoed by the model
        begin
            string s = "uart ok\n";
            for (int i = 0; i < s.len(); i++) send(s[i], 1'b0);
        end

        repeat (2*CPB) @(negedge clk);    // let the model finish the last stop bit
        if (u_rx.active) fail("receiver still inside a frame at the end");

        // ---- verdict
        if (u_rx.bytes.size() != expected.size())
            fail($sformatf("received %0d bytes, expected %0d", u_rx.bytes.size(), expected.size()));
        foreach (expected[i])
            if (i < u_rx.bytes.size() && u_rx.bytes[i] != expected[i])
                fail($sformatf("byte %0d: got %02h, expected %02h", i, u_rx.bytes[i], expected[i]));
        if (u_rx.framing_errors) fail($sformatf("%0d framing error(s)", u_rx.framing_errors));
        if (u_rx.false_starts)   fail($sformatf("%0d false start(s)", u_rx.false_starts));
        if (u_rx.x_samples)      fail($sformatf("%0d X/Z sample(s) on tx", u_rx.x_samples));

        $display("SUMMARY bytes=%0d expected=%0d framing=%0d false_starts=%0d",
                 u_rx.bytes.size(), expected.size(), u_rx.framing_errors, u_rx.false_starts);
        if (errors == 0) $display("UART_TX PASS");
        else             $fatal(1, "UART_TX FAIL: %0d check(s) failed", errors);
        $finish;
    end

    // Watchdog
    initial begin
        repeat (200 * 10 * CPB) @(posedge clk);
        $fatal(1, "UART_TX FAIL: watchdog (tx_busy stuck?)");
    end

    uart_tx #(.CLKS_PER_BIT(CPB)) u_dut (
        .clk     (clk),
        .rst     (rst),
        .tx_valid(tx_valid),
        .tx_data (tx_data),
        .tx_busy (tx_busy),
        .tx      (tx)
    );

    uart_rx_model #(.CLKS_PER_BIT(CPB)) u_rx (
        .clk(clk),
        .rx (tx)
    );
endmodule
