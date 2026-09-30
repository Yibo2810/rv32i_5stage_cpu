`timescale 1ns/1ps

module fpga_sys_tb;
    import single_pkg::*;

    localparam int unsigned MAX_CYCLES  = 10_000;
    localparam string       DEFAULT_MEM = "rtl/fpga/build/hazard_test.mem";

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

    // ---- TB variables
    string       mem;
    logic [31:0] expect_tohost;
    int unsigned cycles;
    bit          timeout;
    int unsigned errors = 0;

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
        $readmemh(path, u_sys.u_imem.rom);
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

    function automatic void report (string name);
        errors++;
        $display("CHECK FAIL, see %s", name);
    endfunction

    initial begin
        if (!$value$plusargs("MEM=%s", mem))                     mem           = DEFAULT_MEM;
        if (!$value$plusargs("EXPECT_TOHOST=%h", expect_tohost)) expect_tohost = 32'h1;

        @(negedge clk);
        load_program(mem);
        apply_reset();
        run_until_halt(MAX_CYCLES, cycles, timeout);

        $display("SUMMARY mem=%s expect_tohost=%08h", mem, expect_tohost);
        $display("SUMMARY cycles=%0d timeout=%0d halted=%0d cause=%s trap_pc=%08h",
                 cycles, timeout, halted, trap_cause_q.name(), trap_pc_q);
        $display("SUMMARY tohost_seen=%0d tohost=%08h pass=%0d fail=%0d error_trap=%0d mark_seen=%0d",
                 tohost_seen, tohost, pass, fail, error_trap, mark_seen);
        if (timeout)
            $display("TIMEOUT: PC = %08h", u_sys.u_core.imem_addr);   // hierarchical peek, no net needed

        if (!halted) report("halted");
        if (trap_cause_q != EXC_BREAKPOINT) report("cause");
        if (!mark_seen) report("mark_seen");
        if (tohost != expect_tohost) report("tohost");
        if (pass != (expect_tohost == 1)) report("pass");
        if (errors == 0) begin
            $display("FPGA_SYS PASS");
            $finish;
        end else begin
            $fatal(1, "FPGA_SYS FAIL: %0d check(s) failed", errors);
        end
    end

    fpga_sys u_sys (
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
        .error_trap  (error_trap)
    );
endmodule
