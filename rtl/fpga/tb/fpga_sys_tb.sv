`timescale 1ns/1ps

module fpga_sys_tb;
    import core_pkg::*;

    localparam string       DEFAULT_MEM = "rtl/fpga/build/mmap_test.mem";
    localparam int          SIM_CPB     = 8;      // UART clocks per bit in sim (board: 217)
    // Wait for an RX echo in CPU cycles, not bit times: software latency does not shrink
    // with SIM_CPB. oled_term page flip measured 794 cycles; normal echo ~260.
    localparam int          ECHO_TIMEOUT = 4000;
    localparam int          SIM_PANIC_PERIOD = 500; // idle cycles between panic lines in sim (board: 1 s)
    localparam int          PANIC_LEN   = 72;     // bytes per halt_reporter line
    localparam int          SIM_OLED_MS = 10;     // oled_seq: clk per "ms" in sim (board: 25_000)
    localparam string       FS_DIR      = "sim/build/fpga_sys_vcs";   // oled.ppm goes here

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
    logic        load_mode = 1'b0;  // sw[2]: hold the core and take a program over UART (uart_loader)
    logic        loading, load_err;

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
    string       load_bin;          // +LOAD_BIN=, program sent over UART to uart_loader (load_mode = 1) instead of $readmemh
    bit          load_corrupt;      // +LOAD_CORRUPT=1: one data byte is flipped on the line, the loader must end in ERR
    bit          load_ok;
    string       load_frame;        // +LOAD_FRAME=, exact bytes to send (tools/uart_load.py --out); default: built here
    int unsigned rx_sent    = 0;
    int unsigned rx_no_echo = 0;
    string       expect_oled_file;  // +EXPECT_OLED_FILE=, rows 1-7 after a PASS halt: "<fg hex4> <text>" per line

    // ---- OLED screen check: reference glyphs read out of oled_font, CPU writes counted
    localparam int OLED_W = 96, OLED_H = 64;
    logic [7:0]  f_ch = '0;
    logic [2:0]  f_gy = '0;
    logic [7:0]  f_bits;
    logic [7:0]  glyph [128][8];
    int unsigned oled_txt_wrs = 0, oled_col_wrs = 0;

    oled_font u_ref_font (.ch(f_ch), .gy(f_gy), .bits(f_bits));

    initial
        for (int ch = 0; ch < 128; ch++)
            for (int gy = 0; gy < 8; gy++) begin
                f_ch = 8'(ch); f_gy = 3'(gy); #1;
                glyph[ch][gy] = f_bits;
            end

    always @(posedge clk) if (!rst) begin
        if (u_sys.oled_txt_wr) oled_txt_wrs++;
        if (u_sys.oled_col_wr) oled_col_wrs++;
    end

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
    // Paced by the echo: the next byte goes out only after the program has echoed and the
    // TX line has gone idle again. An echo can be several bytes ("\b \b", "\r\n") and the core
    // does not read RBR while it is still sending them, so the single-byte RBR never overruns
    // in this test (overrun is covered by uart_16550_tb). Starts after the program's first
    // line (its prompt).
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

    // ---- sw[2] mode: the "PC" sends "RVLD" + len (LE) + image + byte sum (LE) on uart_rxd.
    // With +LOAD_FRAME the bytes come from tools/uart_load.py --out, so the board and the
    // simulation share one frame builder. RAM is filled with ebreak first, so a program
    // that did not arrive over UART halts without writing tohost and fails.
    task automatic load_over_uart(input string path, input bit corrupt, output bit ok);
        logic [7:0]  img[$], frame[$];
        logic [31:0] sum = 0;
        int          fd, c, bad_words = 0, first_bad = -1;
        int unsigned guard = 0;
        ok = 1'b0;
        fd = $fopen(path, "rb");
        if (fd == 0) $fatal(1, "cannot open %s", path);
        while ((c = $fgetc(fd)) != -1) img.push_back(8'(c));
        $fclose(fd);
        while (img.size() % 4 != 0) img.push_back(8'h00);
        foreach (img[i]) sum += img[i];
        if (load_frame != "") begin
            fd = $fopen(load_frame, "rb");
            if (fd == 0) $fatal(1, "cannot open %s", load_frame);
            while ((c = $fgetc(fd)) != -1) frame.push_back(8'(c));
            $fclose(fd);
            if (frame.size() != img.size() + 12) $fatal(1, "%s: %0d bytes, want %0d", load_frame, frame.size(), img.size() + 12);
        end else begin
            frame = {8'h52, 8'h56, 8'h4C, 8'h44};
            for (int k = 0; k < 4; k++) frame.push_back(8'(img.size() >> (8*k)));
            foreach (img[i]) frame.push_back(img[i]);
            for (int k = 0; k < 4; k++) frame.push_back(sum[8*k +: 8]);
        end
        if (corrupt) frame[8 + img.size() / 2] ^= 8'h01;
        $display("LOAD sending %s: %0d bytes, sum %08h, frame from %s", path, img.size(), sum,
                 load_frame != "" ? load_frame : "fpga_sys_tb");
        if (corrupt) $display("LOAD byte %0d flipped on the line (bad checksum expected)", img.size() / 2);

        foreach (frame[i]) uart_send_byte(frame[i]);
        while (loading === 1'b1 && load_err !== 1'b1 && guard < 40 * SIM_CPB) begin
            @(negedge clk);
            guard++;
        end
        $display("SUMMARY load loading=%0b load_err=%0b state=%s", loading, load_err, u_sys.u_uart_loader.state.name());
        if (corrupt) begin
            ok = (load_err === 1'b1 && loading === 1'b1);
            return;
        end
        if (loading !== 1'b0 || load_err !== 1'b0) return;
        // the core left reset on the last clock edge: RAM must hold the image, word for word
        for (int w = 0; w < img.size() / 4; w++)
            if (u_sys.u_ram.mem[w] !== {img[4*w+3], img[4*w+2], img[4*w+1], img[4*w]}) begin
                bad_words++;
                if (first_bad < 0) first_bad = w;
            end
        if (bad_words != 0) begin
            $display("LOAD MISMATCH: %0d / %0d RAM words differ from %s, first at word %0d: %08h",
                     bad_words, img.size() / 4, path, first_bad, u_sys.u_ram.mem[first_bad]);
            return;
        end
        $display("LOAD MATCH: RAM == %s (%0d words), core released", path, img.size() / 4);
        ok = 1'b1;
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
                while (u_rx.bytes.size() <= n_before && guard < ECHO_TIMEOUT) begin
                    @(negedge clk);
                    guard++;
                end
                if (u_rx.bytes.size() <= n_before) begin
                    rx_no_echo++;
                    $display("UART RX: no echo for byte %0d (%02h)", i, txt[i]);
                end else begin
                    wait_uart_idle();   // the rest of a multi-byte echo
                end
            end
        end
    end

    function automatic void report (string name);
        errors++;
        $display("CHECK FAIL, see %s", name);
    endfunction

    // Wait for n frame ends (oled_render PIX -> WIN). After a halt, n = 2 guarantees one whole
    // frame scanned with the final text: the first end may close a frame already in flight.
    task automatic wait_oled_frames(input int n, output bit ok);
        int unsigned guard;
        ok = 1'b1;
        repeat (n) begin
            guard = 0;
            while (u_sys.u_ctrl.u_render.state != 1'b1 && guard < 2_000_000) begin @(negedge clk); guard++; end
            while (u_sys.u_ctrl.u_render.state != 1'b0 && guard < 2_000_000) begin @(negedge clk); guard++; end
            if (guard >= 2_000_000) begin ok = 1'b0; return; end
        end
        repeat (50) @(negedge clk);   // last pixel bytes leave oled_spi
    endtask

    // Expected screen after a PASS halt: row 0 is the PASS bar (from the RTL rule, not the file),
    // rows 1-7 come from the file. Missing lines / short text = blank cells, white.
    task automatic check_oled(input string path);
        string       exp_txt [8];
        logic [15:0] exp_fg  [8];
        logic [15:0] exp_bg  [8];
        string       line;
        int          fd, r, bad, first_r, first_c;
        bit          ok;

        foreach (exp_txt[i]) begin exp_txt[i] = ""; exp_fg[i] = peripherals::RGB_WHITE; exp_bg[i] = peripherals::RGB_BLACK; end
        exp_txt[0] = "PASS        "; exp_fg[0] = peripherals::RGB_BLACK; exp_bg[0] = peripherals::RGB_YELLOW;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "cannot open %s", path);
        r = 1;
        while (r < 8 && $fgets(line, fd)) begin
            while (line.len() > 0 && (line[line.len()-1] == "\n" || line[line.len()-1] == 8'h0d))
                line = line.substr(0, line.len() - 2);
            if (line.len() < 4) $fatal(1, "%s line %0d: want \"<fg hex4> <text>\", got \"%s\"", path, r, line);
            exp_fg[r]  = 16'(line.substr(0, 3).atohex());
            exp_txt[r] = (line.len() > 5) ? line.substr(5, line.len() - 1) : "";
            r++;
        end
        $fclose(fd);

        if (oled_txt_wrs == 0) report("oled_no_writes");   // a blank screen must not pass by accident
        if (!(halted === 1'b1 && pass === 1'b1)) begin
            $display("OLED: not checked, the CPU text is only kept on screen after a PASS halt");
            report("oled_not_pass");
            return;
        end
        wait_oled_frames(2, ok);
        if (!ok) begin
            report("oled_no_frame");
            return;
        end

        bad = 0; first_r = -1; first_c = -1;
        for (int y = 0; y < OLED_H; y++)
            for (int x = 0; x < OLED_W; x++) begin
                automatic int          rr = y / 8, cc = x / 8;
                automatic logic [7:0]  ch = (cc < exp_txt[rr].len()) ? exp_txt[rr][cc] : 8'h20;
                automatic logic [15:0] want = glyph[ch & 8'h7f][y % 8][x % 8] ? exp_fg[rr] : exp_bg[rr];
                if (u_oled.fb[y][x] !== want) begin
                    bad++;
                    if (first_r < 0) begin first_r = rr; first_c = cc; end
                    if (bad <= 3) $display("OLED MISMATCH pixel (%0d,%0d) cell r%0d c%0d '%s': got %04h, want %04h",
                                           x, y, rr, cc, string'(ch), u_oled.fb[y][x], want);
                end
            end
        u_oled.dump_ppm({FS_DIR, "/oled.ppm"});
        $display("SUMMARY oled txt_wr=%0d col_wr=%0d bad_pixels=%0d (%s, picture %s/oled.ppm)",
                 oled_txt_wrs, oled_col_wrs, bad, path, FS_DIR);
        if (bad != 0) begin
            $display("OLED MISMATCH: %0d / 6144 pixels wrong, first in cell r%0d c%0d", bad, first_r, first_c);
            report("oled_frame");
        end else begin
            $display("OLED MATCH: rows 1-7 == %s", path);
        end
    endtask

    initial begin
        if (!$value$plusargs("MEM=%s", mem)) mem = DEFAULT_MEM;
        if (!$value$plusargs("EXPECT_TOHOST=%h", expect_tohost)) expect_tohost = 32'h1;
        if (!$value$plusargs("EXPECT_BUS_ERR=%d", expect_bus_err)) expect_bus_err = 1'b0;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 10_000;

        @(negedge clk);
        if ($value$plusargs("LOAD_BIN=%s", load_bin)) begin
            if (!$value$plusargs("LOAD_CORRUPT=%d", load_corrupt)) load_corrupt = 1'b0;
            if (!$value$plusargs("LOAD_FRAME=%s", load_frame)) load_frame = "";
            mem = load_bin;
            for (int i = 0; i < $size(u_sys.u_ram.mem); i++) u_sys.u_ram.mem[i] = 32'h0010_0073;   // ebreak
            load_mode = 1'b1;                       // sw[2] on before reset is released
            apply_reset();
            load_over_uart(load_bin, load_corrupt, load_ok);
            if (load_corrupt) begin
                // negative test: the loader must refuse the frame and keep the core in reset
                repeat (2000) @(negedge clk);
                if (!load_ok) report("load_err_not_raised");
                if (mark_seen || halted) report("core_ran_after_bad_load");
                if (errors == 0) begin
                    $display("LOAD ERR DETECTED: bad checksum -> load_err=1, core held in reset");
                    $display("FPGA_SYS PASS");
                    $finish;
                end
                $fatal(1, "FPGA_SYS FAIL: %0d check(s) failed", errors);
            end
            if (!load_ok) begin
                report("load");
                $fatal(1, "FPGA_SYS FAIL: program did not load over UART");
            end
        end else begin
            load_program(mem);
            apply_reset();
        end
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
        if ($value$plusargs("EXPECT_OLED_FILE=%s", expect_oled_file)) check_oled(expect_oled_file);
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
        .oled_pmoden (oled_pmoden),
        .load_mode   (load_mode),
        .loading     (loading),
        .load_err    (load_err)
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
