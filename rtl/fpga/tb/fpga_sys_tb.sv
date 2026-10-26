`timescale 1ns/1ps

module fpga_sys_tb;
    import single_pkg::*;

    localparam string       DEFAULT_MEM = "rtl/fpga/build/mmap_test.mem";
    localparam int          SIM_CPB     = 8;      // UART clocks per bit in sim (board: 217)
    localparam int          SIM_PANIC_PERIOD = 500; // idle cycles between panic lines in sim (board: 1 s)
    localparam int          PANIC_LEN   = 72;     // bytes per halt_reporter line
    localparam int          SIM_OLED_MS = 10;     // oled_seq: clk per "ms" in sim (board: 25_000)

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #20 clk = ~clk;   // 40 ns = 25 MHz

    logic        halted;
    exc_cause_e  trap_cause_q;
    logic [31:0] trap_pc_q;
    logic        tohost_seen;
    logic [31:0] tohost;
    logic        pass;
    logic        fail;
    logic        mark_seen;
    logic        error_trap;
    logic        bus_err;
    logic        uart_txd;
    logic        uart_rxd = 1'b1;   // PC -> FPGA line, idle high; driven by the sender below
    logic        oled_cs_n, oled_mosi, oled_sclk, oled_dc, oled_res_n, oled_vccen, oled_pmoden;

    // ---- TB variables
    string       mem;
    logic [31:0] expect_tohost;
    bit          expect_bus_err;   // 0: the program must not touch unmapped space
    int unsigned max_cycles;       // +MAX_CYCLES=, default 10000 (UART output needs more)
    int unsigned cycles;
    bit          timeout;
    int unsigned errors = 0;
    string       expect_uart_file;  // +EXPECT_UART_FILE=, exact expected UART text ("\r\n" counted as "\n")
    logic [31:0] expect_bus_err_addr; // +EXPECT_BUS_ERR_ADDR=, first unmapped address (checked only if given)
    int unsigned n_prog;            // UART bytes sent by the program, before the panic printer took over
    string       uart_rx_file;      // +UART_RX_FILE=, bytes the "PC" types into uart_rxd (trailing CR/LF dropped)
    int unsigned rx_sent    = 0;
    int unsigned rx_no_echo = 0;

    task automatic apply_reset();
        rst = 1'b1;
        repeat (5) @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic load_program(input string path);
        int fd;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "cannot open %s (run simv from the repo root)", path);
        $fclose(fd);
        $readmemh(path, u_sys.u_ram.mem);
    endtask

    task automatic run_until_halt(
        input int unsigned max_cycles,
        output int unsigned cycles,
        output bit timeout
    );
        cycles = 0;
        timeout = 1'b0;
        while (halted !== 1'b1) begin
            if (cycles == max_cycles) begin
                timeout = 1'b1;
                return;
            end
            @(negedge clk);
            cycles++;
        end
    endtask

    // Wait until the line has been idle-high for 12 bit times outside a frame,
    // so a byte still shifting out when the core halts is not lost.
    task automatic wait_uart_idle();
        int unsigned idle  = 0;
        int unsigned guard = 0;
        while (idle < 12 * SIM_CPB && guard < 1_000_000) begin
            @(posedge clk);
            guard++;
            if (uart_txd === 1'b1 && !u_rx.active) idle++;
            else                                   idle = 0;
        end
    endtask

    function automatic string read_file(string path);
        string s = "";
        int    fd, c;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "cannot open %s", path);
        while ((c = $fgetc(fd)) != -1) s = {s, string'(byte'(c))};
        $fclose(fd);
        return s;
    endfunction

    // After halt the panic printer starts once the program's last byte has left uart_tx;
    // by then u_rx has pushed that byte (it samples the stop bit mid-bit), so the count splits the stream.
    task automatic wait_panic_start(output int unsigned n);
        int unsigned guard = 0;
        do begin
            @(negedge clk);
            guard++;
        end while (!(u_sys.panic_tx_valid && !u_sys.uart_tx_busy) && guard < 1_000_000);
        n = u_rx.bytes.size();
    endtask

    task automatic wait_uart_bytes(input int unsigned n);
        int unsigned guard = 0;
        while (u_rx.bytes.size() < n && guard < 2_000_000) begin
            @(negedge clk);
            guard++;
        end
    endtask

    function automatic string uart_raw(int unsigned from, int unsigned to);
        string s = "";
        for (int unsigned i = from; i < to && i < u_rx.bytes.size(); i++) s = {s, string'(u_rx.bytes[i])};
        return s;
    endfunction

    // Program bytes [0, n_prog) with every "\r\n" folded to "\n" (print_puts sends CRLF for terminals).
    // A NUL byte is written as the text "\x00": string'(8'h00) is the empty string in SV,
    // so a raw NUL would vanish from the comparison.
    function automatic string uart_text_lf();
        string s = "";
        for (int i = 0; i < n_prog; i++) begin
            if (u_rx.bytes[i] == 8'h0d && i + 1 < n_prog && u_rx.bytes[i+1] == 8'h0a) continue;
            if (u_rx.bytes[i] == 8'h00) s = {s, "\\x00"};
            else                        s = {s, string'(u_rx.bytes[i])};
        end
        return s;
    endfunction

    // ---- PC -> FPGA sender: 8N1 on real time (not on clk), random phase per frame.
    // Paced by the echo: the next byte goes out only after the program has sent one byte
    // back, so the single-byte RBR never overruns in this test (overrun is covered by
    // uart_16550_tb). Starts after the program's first line (its prompt).
    localparam realtime RX_BIT_NS = SIM_CPB * 40.0;

    task automatic uart_send_byte(input logic [7:0] b);
        #($urandom_range(0, 39999) * 1ps);
        uart_rxd = 1'b0;
        #(RX_BIT_NS);
        for (int i = 0; i < 8; i++) begin
            uart_rxd = b[i];
            #(RX_BIT_NS);
        end
        uart_rxd = 1'b1;
        #(RX_BIT_NS);
    endtask

    function automatic bit uart_seen_lf();
        foreach (u_rx.bytes[i]) if (u_rx.bytes[i] == 8'h0a) return 1'b1;
        return 1'b0;
    endfunction

    initial begin
        string       txt;
        int unsigned guard, n_before;
        if ($value$plusargs("UART_RX_FILE=%s", uart_rx_file)) begin
            txt = read_file(uart_rx_file);
            while (txt.len() > 0 && (txt[txt.len()-1] == "\n" || txt[txt.len()-1] == 8'h0d))
                txt = txt.substr(0, txt.len() - 2);
            @(negedge rst);
            guard = 0;
            while (!uart_seen_lf() && guard < 1_000_000) begin
                @(negedge clk);
                guard++;
            end
            for (int i = 0; i < txt.len(); i++) begin
                n_before = u_rx.bytes.size();
                uart_send_byte(txt[i]);
                rx_sent++;
                guard = 0;
                while (u_rx.bytes.size() <= n_before && guard < 40 * SIM_CPB) begin
                    @(negedge clk);
                    guard++;
                end
                if (u_rx.bytes.size() <= n_before) begin
                    rx_no_echo++;
                    $display("UART RX: no echo for byte %0d (%02h)", i, txt[i]);
                end
            end
        end
    end

    function automatic void report (string name);
        errors++;
        $display("CHECK FAIL, see %s", name);
    endfunction

    initial begin
        if (!$value$plusargs("MEM=%s", mem)) mem = DEFAULT_MEM;
        if (!$value$plusargs("EXPECT_TOHOST=%h", expect_tohost)) expect_tohost = 32'h1;
        if (!$value$plusargs("EXPECT_BUS_ERR=%d", expect_bus_err)) expect_bus_err = 1'b0;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 10_000;

        @(negedge clk);
        load_program(mem);
        apply_reset();
        run_until_halt(max_cycles, cycles, timeout);
        if (halted === 1'b1) begin
            wait_panic_start(n_prog);
            wait_uart_bytes(n_prog + 2 * PANIC_LEN);
        end else begin
            n_prog = u_rx.bytes.size();
        end
        wait_uart_idle();

        $display("SUMMARY mem=%s expect_tohost=%08h", mem, expect_tohost);
        $display("SUMMARY cycles=%0d timeout=%0d halted=%0d cause=%s trap_pc=%08h",
                 cycles, timeout, halted, trap_cause_q.name(), trap_pc_q);
        $display("SUMMARY tohost_seen=%0d tohost=%08h pass=%0d fail=%0d error_trap=%0d mark_seen=%0d",
                 tohost_seen, tohost, pass, fail, error_trap, mark_seen);
        $display("SUMMARY bus_err=%0d expect_bus_err=%0d", bus_err, expect_bus_err);
        $display("SUMMARY uart bytes=%0d framing=%0d false_starts=%0d x_samples=%0d",
                 u_rx.bytes.size(), u_rx.framing_errors, u_rx.false_starts, u_rx.x_samples);
        if (timeout)
            $display("TIMEOUT: PC = %08h", u_sys.u_core.imem_req_addr);   // hierarchical peek, no net needed

        if (!halted) report("halted");
        if (trap_cause_q != EXC_BREAKPOINT) report("cause");
        if (!mark_seen) report("mark_seen");
        if (tohost != expect_tohost) report("tohost");
        if (pass != (expect_tohost == 1)) report("pass");
        if (bus_err != expect_bus_err) report("bus_err");
        if (u_rx.framing_errors || u_rx.false_starts || u_rx.x_samples) report("uart_frame");
        if (uart_rx_file != "") begin
            $display("SUMMARY uart_rx sent=%0d no_echo=%0d (%s)", rx_sent, rx_no_echo, uart_rx_file);
            if (rx_no_echo != 0) report("uart_rx_echo");
        end
        if ($value$plusargs("EXPECT_UART_FILE=%s", expect_uart_file)) begin
            automatic string want = read_file(expect_uart_file);
            automatic string got  = uart_text_lf();
            if (got != want) begin
                $display("UART MISMATCH: got %0d chars, expected %0d (%s)", got.len(), want.len(), expect_uart_file);
                $display("  got : \"%s\"", got);
                $display("  want: \"%s\"", want);
                report("uart_text");
            end else begin
                $display("UART MATCH: %0d chars == %s", got.len(), expect_uart_file);
            end
        end else if (n_prog != 0) begin
            $display("NOTE: %0d UART bytes received, no +EXPECT_UART_FILE given", n_prog);
        end
        if ($value$plusargs("EXPECT_BUS_ERR_ADDR=%h", expect_bus_err_addr)) begin
            $display("SUMMARY bus_err_addr=%08h expect=%08h", u_sys.bus_err_addr, expect_bus_err_addr);
            if (u_sys.bus_err_addr !== expect_bus_err_addr) report("bus_err_addr");
        end
        if (halted === 1'b1) begin
            automatic int unsigned errors_before = errors;
            automatic string want = $sformatf("\015\012HALT %s cause=%1h pc=%08h tohost=%08h buserr=%0d addr=%08h\015\012",
                                              pass ? "PASS" : "FAIL", trap_cause_q, trap_pc_q, tohost, bus_err, u_sys.bus_err_addr);
            for (int k = 0; k < 2; k++) begin
                automatic string got = uart_raw(n_prog + k * PANIC_LEN, n_prog + (k + 1) * PANIC_LEN);
                if (got != want) begin
                    $display("PANIC MISMATCH line %0d:\n  got  '%s'\n  want '%s'", k, got, want);
                    report("panic_line");
                end
            end
            if (u_rx.bytes.size() != n_prog + 2 * PANIC_LEN) begin
                $display("PANIC MISMATCH: %0d bytes after the program, expected %0d", u_rx.bytes.size() - n_prog, 2 * PANIC_LEN);
                report("panic_count");
            end
            if (errors == errors_before) $display("PANIC MATCH: 2 lines x %0d bytes", PANIC_LEN);
        end
        if (errors == 0) begin
            $display("FPGA_SYS PASS");
            $finish;
        end else begin
            $fatal(1, "FPGA_SYS FAIL: %0d check(s) failed", errors);
        end
    end

    fpga_sys #(.UART_CLKS_PER_BIT(SIM_CPB), .PANIC_PERIOD(SIM_PANIC_PERIOD), .OLED_MS_CYCLES(SIM_OLED_MS)) u_sys (
        .clk         (clk),
        .rst         (rst),
        .halted      (halted),
        .trap_cause_q(trap_cause_q),
        .trap_pc_q   (trap_pc_q),
        .tohost_seen (tohost_seen),
        .tohost      (tohost),
        .pass        (pass),
        .fail        (fail),
        .mark_seen   (mark_seen),
        .error_trap  (error_trap),
        .bus_err     (bus_err),
        .uart_txd    (uart_txd),
        .uart_rxd    (uart_rxd),
        .oled_cs_n   (oled_cs_n),
        .oled_mosi   (oled_mosi),
        .oled_sclk   (oled_sclk),
        .oled_dc     (oled_dc),
        .oled_res_n  (oled_res_n),
        .oled_vccen  (oled_vccen),
        .oled_pmoden (oled_pmoden)
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

    uart_rx_model #(.CLKS_PER_BIT(SIM_CPB)) u_rx (
        .clk(clk),
        .rx (uart_txd)
    );
endmodule
