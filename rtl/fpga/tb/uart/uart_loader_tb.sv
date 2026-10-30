`timescale 1ns/1ps
// uart_loader unit test: drives rx_valid / rx_data directly (one-cycle pulse per byte, like
// uart_rx), a word-addressed RAM model takes wr_valid / wr_addr / wr_data.
// Frame: "RVLD" + len (4 B, little endian) + len data bytes + sum of data bytes (4 B, LE).
//   make loader-test
// Cases: magic timing (LEN exactly one byte after D), good frame with an all-zero word,
// resync on "RRVLD" and garbage, lone 'D', abort in the middle of the magic, bad checksum,
// illegal lengths, switch off, no activity while load_mode = 0.
module uart_loader_tb;
    import peripherals::*;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #20 clk = ~clk;

    logic        load_mode = 1'b0;
    logic        rx_valid  = 1'b0;
    logic [7:0]  rx_data   = '0;
    logic        loading, load_err, wr_valid;
    logic [31:0] wr_addr, wr_data;
    logic [3:0]  wr_strb;

    uart_loader dut (.*);

    // ---- RAM model: 64 KB, word addressed like sys_ram (addr[15:2])
    logic [31:0] mem [16384];
    int unsigned writes = 0, bad_strb = 0, writes_outside_data = 0;
    always @(posedge clk) if (wr_valid) begin
        mem[wr_addr[15:2]] <= wr_data;
        writes++;
        if (wr_strb !== 4'b1111) bad_strb++;
        if (dut.state != dut.DATA) writes_outside_data++;
    end

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        $display("CHECK FAIL: %s", msg);
    endtask

    // one byte = one-cycle rx_valid pulse, then an idle gap (real uart_rx: ~2170 cycles)
    task automatic send_byte(input logic [7:0] b, input int gap = 6);
        @(negedge clk); rx_valid = 1'b1; rx_data = b;
        @(negedge clk); rx_valid = 1'b0; rx_data = 8'hxx;
        repeat (gap) @(negedge clk);
    endtask

    task automatic send_bytes(input logic [7:0] q[$]);
        foreach (q[i]) send_byte(q[i]);
    endtask

    function automatic void push32(ref logic [7:0] q[$], input logic [31:0] v);
        for (int k = 0; k < 4; k++) q.push_back(v[8*k +: 8]);
    endfunction

    // frame = magic + len + data + sum; sum_xor flips sum bits to make it wrong
    function automatic void build_frame(ref logic [7:0] q[$], input logic [7:0] data[$],
                                        input logic [31:0] len, input logic [31:0] sum_xor = 0);
        logic [31:0] sum = 0;
        q = {8'h52, 8'h56, 8'h4C, 8'h44};
        push32(q, len);
        foreach (data[i]) begin q.push_back(data[i]); sum += data[i]; end
        push32(q, sum ^ sum_xor);
    endfunction

    task automatic switch_off_on();
        @(negedge clk); load_mode = 1'b0;
        repeat (3) @(negedge clk);
        if (loading !== 1'b0 || load_err !== 1'b0)
            fail($sformatf("switch off: loading=%0b load_err=%0b, want 0/0", loading, load_err));
        load_mode = 1'b1;
        repeat (2) @(negedge clk);
    endtask

    task automatic expect_state(input string what, input bit want_loading, input bit want_err);
        if (loading !== want_loading || load_err !== want_err)
            fail($sformatf("%s: loading=%0b load_err=%0b (state %s), want %0b/%0b",
                           what, loading, load_err, dut.state.name(), want_loading, want_err));
    endtask

    logic [7:0] data[$], frame[$];
    int unsigned w0;
    logic [31:0] bad_len [3] = '{32'd0, 32'd6, 32'd65540};

    initial begin
        foreach (mem[i]) mem[i] = 32'hDEAD_BEEF;   // "previous program": every word must be overwritten
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // ---- T0 load_mode = 0: bytes on the line are ignored, CPU not held
        send_bytes('{8'h52, 8'h56, 8'h4C, 8'h44, 8'h04, 8'h00});
        expect_state("T0 load_mode=0", 0, 0);
        if (writes != 0) fail("T0: RAM written while load_mode = 0");

        // ---- T1 magic timing: the byte right after 'D' must already be length byte 0
        load_mode = 1'b1;
        repeat (2) @(negedge clk);
        expect_state("T1 waiting for magic", 1, 0);
        send_bytes('{8'h52, 8'h56, 8'h4C});
        send_byte(8'h44, 0);                          // no gap: look at the very next cycle
        if (dut.state != dut.LEN)
            fail($sformatf("T1: one cycle after 'D' state is %s, want LEN", dut.state.name()));
        else $display("T1 magic: state = LEN one cycle after 'D' (no extra cycle)");

        // ---- T1b finish that frame: 16 bytes, word 2 is all zero, sum must match
        data = '{8'h13, 8'h05, 8'h10, 8'h00,  8'h73, 8'h00, 8'h10, 8'h00,
                 8'h00, 8'h00, 8'h00, 8'h00,  8'hEF, 8'hBE, 8'hAD, 8'hDE};
        build_frame(frame, data, 16);
        frame = frame[4:$];                           // magic already sent
        send_bytes(frame);
        expect_state("T1 after a good frame (switch still on)", 0, 0);
        if (dut.state != dut.DONE) fail($sformatf("T1: state %s after a good frame, want DONE", dut.state.name()));
        if (mem[0] !== 32'h0010_0513 || mem[1] !== 32'h0010_0073 || mem[2] !== 32'h0000_0000 || mem[3] !== 32'hDEAD_BEEF)
            fail($sformatf("T1: RAM %08h %08h %08h %08h, want 00100513 00100073 00000000 deadbeef",
                           mem[0], mem[1], mem[2], mem[3]));
        if (writes != 4) fail($sformatf("T1: %0d RAM writes, want 4 (one per word)", writes));
        if (mem[4] !== 32'hDEAD_BEEF) fail("T1: wrote past len");

        // ---- T2 resync: garbage, then "RRVLD" (first R is a leftover) must still be found
        switch_off_on();
        foreach (mem[i]) mem[i] = 32'hDEAD_BEEF;
        w0 = writes;
        data = '{8'h11, 8'h22, 8'h33, 8'h44};
        build_frame(frame, data, 4);
        send_bytes('{8'h00, 8'h44, 8'h52, 8'h56, 8'h00, 8'h52});   // "D" alone, "RV" broken, then R
        send_bytes(frame);                                          // starts with R V L D -> R R V L D
        if (dut.state != dut.DONE) fail($sformatf("T2 resync: state %s, want DONE", dut.state.name()));
        if (mem[0] !== 32'h4433_2211) fail($sformatf("T2: RAM[0] %08h, want 44332211", mem[0]));
        if (writes - w0 != 1) fail($sformatf("T2: %0d writes, want 1", writes - w0));

        // ---- T3 a lone 'D' (0x44) must not start a frame
        switch_off_on();
        send_bytes('{8'h44, 8'h04, 8'h00, 8'h00, 8'h00});
        if (dut.state != dut.MAGIC) fail($sformatf("T3 lone D: state %s, want MAGIC", dut.state.name()));

        // ---- T4 abort in the middle of the magic: "RV", switch off/on, then "LD" must NOT complete it
        switch_off_on();
        send_bytes('{8'h52, 8'h56});
        switch_off_on();
        send_bytes('{8'h4C, 8'h44});
        if (dut.state != dut.MAGIC)
            fail($sformatf("T4 abort mid-magic: \"RV\" + off/on + \"LD\" -> state %s, want MAGIC", dut.state.name()));

        // ---- T5 bad checksum -> ERR, CPU held, error LED; switch off clears it
        switch_off_on();
        data = '{8'h01, 8'h02, 8'h03, 8'h04};
        build_frame(frame, data, 4, 32'h1);
        send_bytes(frame);
        expect_state("T5 bad checksum", 1, 1);
        switch_off_on();
        expect_state("T5 after switch off/on", 1, 0);

        // ---- T6 illegal lengths -> ERR right after the 4th length byte
        foreach (bad_len[k]) begin
            switch_off_on();
            frame = {8'h52, 8'h56, 8'h4C, 8'h44};
            push32(frame, bad_len[k]);
            send_bytes(frame);
            expect_state($sformatf("T6 len=%0d", bad_len[k]), 1, 1);
        end

        // ---- T7 largest legal length is accepted (no ERR after the length field)
        switch_off_on();
        frame = {8'h52, 8'h56, 8'h4C, 8'h44};
        push32(frame, 32'd65536);
        send_bytes(frame);
        if (dut.state != dut.DATA) fail($sformatf("T7 len=65536: state %s, want DATA", dut.state.name()));

        @(negedge clk); load_mode = 1'b0;
        repeat (3) @(negedge clk);
        if (bad_strb)            fail($sformatf("%0d writes with wr_strb != 1111", bad_strb));
        if (writes_outside_data) fail($sformatf("%0d writes outside DATA", writes_outside_data));

        $display("SUMMARY writes=%0d errors=%0d", writes, errors);
        if (errors == 0) $display("UART_LOADER PASS");
        else             $display("UART_LOADER FAIL");
        $finish;
    end

    initial begin
        #5ms;
        $display("UART_LOADER FAIL: global timeout");
        $finish;
    end
endmodule
