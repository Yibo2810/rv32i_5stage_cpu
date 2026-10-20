`timescale 1ns/1ps
// TB-only UART receiver (8N1), written independently of the RTL uart_tx so the
// two do not share a misreading of the frame format.
// Start bit: falling edge, re-checked at mid-bit. Data: LSB first, sampled at
// mid-bit. Stop bit must be 1. Echoes each '\n'-terminated line as [UART] ...
module uart_rx_model #(
    parameter int CLKS_PER_BIT = 217
) (
    input logic clk,
    input logic rx
);
    byte unsigned bytes[$];               // everything received, in order
    int unsigned  framing_errors = 0;     // stop bit != 1
    int unsigned  false_starts   = 0;     // falling edge but not 0 at mid start bit
    int unsigned  x_samples      = 0;     // X/Z on the line at a sample point
    bit           active         = 1'b0;  // inside a frame
    string        line           = "";

    function automatic string text();
        string s = "";
        foreach (bytes[i]) s = {s, string'(bytes[i])};
        return s;
    endfunction

    function automatic void clear();
        bytes.delete();
        framing_errors = 0;
        false_starts   = 0;
        x_samples      = 0;
        line           = "";
    endfunction

    initial forever begin
        logic [7:0] b;
        @(negedge rx);                    // X->0 counts too: a tx that resets to 0 is caught
        active = 1'b1;
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        if (rx !== 1'b0) begin
            false_starts++;
            $display("[UART] %0t false start (rx=%b at mid start bit)", $time, rx);
            active = 1'b0;
            continue;
        end
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            if ($isunknown(rx)) x_samples++;
            b[i] = rx;
        end
        repeat (CLKS_PER_BIT) @(posedge clk);
        if (rx !== 1'b1) begin
            framing_errors++;
            $display("[UART] %0t framing error: stop bit = %b, byte = %02h", $time, rx, b);
        end
        bytes.push_back(b);
        if (b == 8'h0a) begin
            $display("[UART] %s", line);
            line = "";
        end else if (b inside {[8'h20:8'h7e]}) begin
            line = {line, string'(b)};
        end else if (b != 8'h0d) begin
            line = {line, $sformatf("\\x%02h", b)};   // keep the log printable
        end
        active = 1'b0;                    // now in the stop bit's second half
    end
endmodule
