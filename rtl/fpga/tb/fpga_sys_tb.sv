`timescale 1ns/1ps

module fpga_sys_tb;
    import single_pkg::*;

    localparam string       DEFAULT_MEM = "rtl/fpga/build/mmap_test.mem";
    localparam int          SIM_CPB     = 8;      // UART clocks per bit in sim (board: 217)

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

    // ---- TB variables
    string       mem;
    logic [31:0] expect_tohost;
    bit          expect_bus_err;   // 0: the program must not touch unmapped space
    int unsigned max_cycles;       // +MAX_CYCLES=, default 10000 (UART output needs more)
    int unsigned cycles;
    bit          timeout;
    int unsigned errors = 0;
    string       expect_uart_file;  // +EXPECT_UART_FILE=, exact expected UART text ("\r\n" counted as "\n")

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

    // Received bytes with every "\r\n" folded to "\n" (print_puts sends CRLF for terminals)
    function automatic string uart_text_lf();
        string s = "";
        for (int i = 0; i < u_rx.bytes.size(); i++) begin
            if (u_rx.bytes[i] == 8'h0d && i + 1 < u_rx.bytes.size() && u_rx.bytes[i+1] == 8'h0a) continue;
            s = {s, string'(u_rx.bytes[i])};
        end
        return s;
    endfunction

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
        if ($value$plusargs("EXPECT_UART_FILE=%s", expect_uart_file)) begin
            automatic string want = read_file(expect_uart_file);
            automatic string got  = uart_text_lf();
            if (got != want) begin
                $display("UART MISMATCH: got %0d chars, expected %0d (%s)", got.len(), want.len(), expect_uart_file);
                report("uart_text");
            end else begin
                $display("UART MATCH: %0d chars == %s", got.len(), expect_uart_file);
            end
        end else if (u_rx.bytes.size() != 0) begin
            $display("NOTE: %0d UART bytes received, no +EXPECT_UART_FILE given", u_rx.bytes.size());
        end
        if (errors == 0) begin
            $display("FPGA_SYS PASS");
            $finish;
        end else begin
            $fatal(1, "FPGA_SYS FAIL: %0d check(s) failed", errors);
        end
    end

    fpga_sys #(.UART_CLKS_PER_BIT(SIM_CPB)) u_sys (
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
        .uart_txd    (uart_txd)
    );

    uart_rx_model #(.CLKS_PER_BIT(SIM_CPB)) u_rx (
        .clk(clk),
        .rx (uart_txd)
    );
endmodule
