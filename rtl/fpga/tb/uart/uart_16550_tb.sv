`timescale 1ns/1ps
// Register-level unit test for uart_16550 (no uart_tx / uart_rx: their ports are driven
// directly, so the status-bit corners can be hit on an exact cycle).
//   make uart-16550-test
// Test points follow the vault note "16550 寄存器完整参考" §9:
//   reset values; DR/OE/FE set and clear; overrun keeps the newest byte; frame_err held
//   high without rx_valid does not re-set FE; DLAB=1 read of n=0 returns DLL without
//   clearing DR; rx_valid in the same cycle as an RBR read or an LSR read (set wins);
//   THR write -> tx_valid/tx_data only when DLAB=0; THRE/TEMT follow tx_busy;
//   config registers read back; IIR = 01.
module uart_16550_tb;
    localparam logic [2:0] N_RBR = 3'd0, N_IER = 3'd1, N_IIR = 3'd2, N_LCR = 3'd3,
                           N_MCR = 3'd4, N_LSR = 3'd5, N_MSR = 3'd6, N_SCR = 3'd7;

    logic       clk = 1'b0;
    logic       rst = 1'b1;
    always #20 clk = ~clk;

    logic       wr_en = 1'b0, rd_en = 1'b0;
    logic [2:0] addr  = '0;
    logic [7:0] wdata = '0;
    logic       tx_busy = 1'b0;
    logic [7:0] rdata, tx_data;
    logic       tx_valid;
    logic       rx_valid = 1'b0, rx_frame_err = 1'b0;
    logic [7:0] rx_data = '0;

    int unsigned errors = 0;
    task automatic fail(input string msg);
        errors++;
        $display("CHECK FAIL @%0t: %s", $time, msg);
    endtask

    // ---- bus helpers: one access per cycle, signals change at negedge
    task automatic wr(input logic [2:0] n, input logic [7:0] d);
        @(negedge clk);
        addr = n; wdata = d; wr_en = 1'b1;
        @(negedge clk);
        wr_en = 1'b0;
    endtask

    // Read samples rdata in the cycle the access fires (rdata is combinational; mmio_regs
    // registers it on that same edge, together with any clear side effect).
    task automatic rd(input logic [2:0] n, output logic [7:0] d);
        @(negedge clk);
        addr = n; rd_en = 1'b1;
        #1 d = rdata;
        @(negedge clk);
        rd_en = 1'b0;
    endtask

    task automatic expect_rd(input logic [2:0] n, input logic [7:0] want, input string what);
        logic [7:0] d;
        rd(n, d);
        if (d !== want) fail($sformatf("%s: read n=%0d got %02h, expected %02h", what, n, d, want));
    endtask

    // one-cycle pulse from the receiver
    task automatic rx_byte(input logic [7:0] b, input logic ferr = 1'b0);
        @(negedge clk);
        rx_valid = 1'b1; rx_data = b; rx_frame_err = ferr;
        @(negedge clk);
        rx_valid = 1'b0;
    endtask

    initial begin
        logic [7:0] d;
        int         n_tx;

        repeat (3) @(negedge clk);
        rst = 1'b0;

        // T1 reset values
        expect_rd(N_LSR, 8'h60, "T1 reset LSR");
        expect_rd(N_IIR, 8'h01, "T1 reset IIR");
        expect_rd(N_LCR, 8'h00, "T1 reset LCR");

        // T2 one byte: DR set, RBR read returns it and clears DR
        rx_byte(8'hA5);
        expect_rd(N_LSR, 8'h61, "T2 LSR after one byte");
        expect_rd(N_RBR, 8'hA5, "T2 RBR");
        expect_rd(N_LSR, 8'h60, "T2 LSR after RBR read");

        // T3 overrun: newest byte kept, OE set, LSR read clears OE only
        rx_byte(8'h11);
        rx_byte(8'h22);
        expect_rd(N_LSR, 8'h63, "T3 LSR after overrun");
        expect_rd(N_LSR, 8'h61, "T3 LSR second read (OE cleared, DR kept)");
        expect_rd(N_RBR, 8'h22, "T3 RBR keeps the newest byte");
        expect_rd(N_LSR, 8'h60, "T3 LSR after RBR read");

        // T4 framing error: FE + DR, LSR read clears FE
        rx_byte(8'h5A, 1'b1);
        expect_rd(N_LSR, 8'h69, "T4 LSR after bad stop bit");
        expect_rd(N_LSR, 8'h61, "T4 LSR second read (FE cleared)");
        expect_rd(N_RBR, 8'h5A, "T4 RBR still delivers the byte");

        // T5 uart_rx.frame_err is a held level: high without rx_valid must not set FE
        @(negedge clk); rx_frame_err = 1'b1;
        repeat (3) @(negedge clk);
        expect_rd(N_LSR, 8'h60, "T5 frame_err held high, no rx_valid");
        @(negedge clk); rx_frame_err = 1'b0;

        // T6 DLAB=1: n=0 reads DLL and does not clear DR; n=1 reads DLM
        rx_byte(8'h77);
        wr(N_LCR, 8'h83);                  // DLAB=1, 8N1
        wr(N_RBR, 8'h0D);                  // DLL
        wr(N_IER, 8'h01);                  // DLM
        expect_rd(N_RBR, 8'h0D, "T6 DLL read back");
        expect_rd(N_IER, 8'h01, "T6 DLM read back");
        expect_rd(N_LSR, 8'h61, "T6 DR untouched by the DLL read");
        wr(N_LCR, 8'h03);                  // DLAB=0
        expect_rd(N_RBR, 8'h77, "T6 RBR after DLAB cleared");

        // T7 rx_valid in the same cycle as an RBR read: old byte returned, DR stays 1
        rx_byte(8'h31);
        @(negedge clk);
        addr = N_RBR; rd_en = 1'b1; rx_valid = 1'b1; rx_data = 8'h32;
        #1 d = rdata;
        @(negedge clk);
        rd_en = 1'b0; rx_valid = 1'b0;
        if (d !== 8'h31) fail($sformatf("T7 RBR read got %02h, expected the old byte 31", d));
        expect_rd(N_LSR, 8'h61, "T7 DR kept after same-cycle read + new byte (no OE)");
        expect_rd(N_RBR, 8'h32, "T7 RBR holds the new byte");

        // T8 rx_valid with frame_err in the same cycle as an LSR read: FE survives
        @(negedge clk);
        addr = N_LSR; rd_en = 1'b1; rx_valid = 1'b1; rx_data = 8'h44; rx_frame_err = 1'b1;
        #1 d = rdata;
        @(negedge clk);
        rd_en = 1'b0; rx_valid = 1'b0; rx_frame_err = 1'b0;
        if (d !== 8'h60) fail($sformatf("T8 LSR read got %02h, expected the old value 60", d));
        expect_rd(N_LSR, 8'h69, "T8 FE and DR set although LSR was read that cycle");
        expect_rd(N_RBR, 8'h44, "T8 RBR");

        // T9 TX path: THR write gives tx_valid + tx_data only with DLAB=0; THRE/TEMT = !tx_busy
        n_tx = 0;
        fork
            begin : count_tx
                forever begin
                    @(posedge clk);
                    if (tx_valid === 1'b1) begin
                        n_tx++;
                        if (tx_data !== 8'h48) fail($sformatf("T9 tx_data %02h, expected 48", tx_data));
                    end
                end
            end
        join_none
        wr(N_RBR, 8'h48);                  // THR, DLAB=0
        wr(N_LCR, 8'h80);
        wr(N_RBR, 8'h99);                  // DLL, must not transmit
        wr(N_LCR, 8'h03);
        disable count_tx;
        if (n_tx != 1) fail($sformatf("T9 %0d tx_valid cycles, expected exactly 1 (DLL write must not transmit)", n_tx));
        @(negedge clk); tx_busy = 1'b1;
        expect_rd(N_LSR, 8'h00, "T9 LSR while tx_busy");
        @(negedge clk); tx_busy = 1'b0;
        expect_rd(N_LSR, 8'h60, "T9 LSR after tx_busy drops");

        // T10 config registers read back
        wr(N_IER, 8'h0F); expect_rd(N_IER, 8'h0F, "T10 IER");
        wr(N_MCR, 8'h1B); expect_rd(N_MCR, 8'h1B, "T10 MCR");
        wr(N_SCR, 8'hC3); expect_rd(N_SCR, 8'hC3, "T10 SCR");
        expect_rd(N_LCR, 8'h03, "T10 LCR");
        expect_rd(N_MSR, 8'h00, "T10 MSR");
        expect_rd(N_IIR, 8'h01, "T10 IIR");

        $display("SUMMARY errors=%0d", errors);
        if (errors == 0) $display("UART_16550 PASS");
        else             $display("UART_16550 FAIL");
        $finish;
    end

    uart_16550 dut (
        .clk         (clk),
        .rst         (rst),
        .wr_en       (wr_en),
        .addr        (addr),
        .wdata       (wdata),
        .tx_busy     (tx_busy),
        .rdata       (rdata),
        .tx_data     (tx_data),
        .tx_valid    (tx_valid),
        .rd_en       (rd_en),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .rx_frame_err(rx_frame_err)
    );
endmodule
