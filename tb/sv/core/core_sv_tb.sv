`timescale 1ns/1ps

import rv_random_pkg::*;

module core_sv_tb;

    logic clk;
    logic rst;
    rv_ref_model ref_model;
    int unsigned pass_cnt = 0;
    int unsigned fail_cnt = 0;
    localparam int NUM_SEEDS = 20;

    task automatic apply_reset();
        rst = 1'b1;
        repeat (2) @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic run_until_pc(input int unsigned stop_bytes, input int unsigned cap);
        for (int c = 0; c < cap; c++) begin
            @(mem_if.cb);
            if (mem_if.cb.imem_addr >= stop_bytes) return;
            @(negedge clk);
        end
        $error("random: watchdog — PC has remained stuck in the program area (suspected JALR jump gone wild)");
    endtask

    function automatic bit check_final_regs(input string name);
        logic [31:0] dut_regs[0:31];
        for (int i = 0; i < 32; i++)
            dut_regs[i] = u_core.u_regfile.regs[i];
        return u_scoreboard.check_regfile(name, dut_regs, ref_model.regs);
    endfunction

    task automatic record(input string name, input bit ok);
        if (ok) pass_cnt++;
        else begin
            fail_cnt++;
            $display("  -> FAIL: %s", name);
        end
    endtask

    task automatic run_random_test(input int seed);
        rv_program p = new();
        string nm = $sformatf("random_seed_%0d", seed);
        bit ok = 1'b1;
        int unsigned prog_bytes;

        p.build(seed);
        u_memory.init_mem();
        p.load_imem(u_memory.imem);
        prog_bytes = p.instrs.size() * 4;

        ref_model = new();
        ref_model.run_iss(u_memory.imem, p.instrs.size());

        u_monitor.clear();
        apply_reset();
        run_until_pc(prog_bytes, 4000);

        ok &= u_scoreboard.check(nm, ref_model.expected_txns, u_monitor.observed_txns);
        ok &= check_final_regs(nm);
        record(nm, ok);
    endtask

    initial begin
        clk = 0;
        rst = 1;
        always #5 clk = ~clk;
        for (int s = 1; s <= NUM_SEEDS; s++)
            run_random_test(s);

        $display("========================================");
        $display("SUMMARY: %0d passed, %0d failed (total %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");
        if (fail_cnt != 0)
            $fatal(1, "RANDOM REGRESSION FAILED: %0d/%0d", fail_cnt, pass_cnt + fail_cnt);
        $display("ALL RANDOM TESTS PASSED");
        $finish;
    end

    core_mem_if mem_if(
        .clk(clk),
        .rst(rst)
    );

    core_single_cycle u_core(
        .clk(clk),
        .rst(rst),
        .imem_addr(mem_if.imem_addr),
        .imem_rdata(mem_if.imem_rdata),
        .dmem_read(mem_if.dmem_read),
        .dmem_write(mem_if.dmem_write),
        .dmem_addr(mem_if.dmem_addr),
        .dmem_wdata(mem_if.dmem_wdata),
        .dmem_wstrb(mem_if.dmem_wstrb),
        .dmem_rdata(mem_if.dmem_rdata),
        .sys_ecall(mem_if.sys_ecall),
        .sys_ebreak(mem_if.sys_ebreak)
    );

    core_memory_model u_memory(
        .mem(mem_if)
    );

    core_monitor u_monitor(
        .mem(mem_if)
    );

    core_scoreboard u_scoreboard();

    core_assertions u_assertions(mem_if.monitor);
endmodule