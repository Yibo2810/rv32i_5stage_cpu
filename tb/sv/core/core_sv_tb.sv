`timescale 1ns/1ps

import rv_random_pkg::*;

module core_sv_tb;

    logic clk;
    logic rst;
    rv_ref_model ref_model;
    int unsigned pass_cnt = 0;
    int unsigned fail_cnt = 0;
    int unsigned num_seeds = 30;
    int unsigned total_txns = 0;
    int unsigned total_retired = 0;
    int unsigned total_static = 0;
    int          single_seed;
    int seed_offset = 0;

    bit single_seed_mode = 1'b0;
    localparam int VACUOUS_K = 12;
    localparam int unsigned RUN_BUDGET = 2000;

    task automatic apply_reset();
        rst = 1'b1;
        repeat (2) @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic run_program(
        input  int unsigned stop_bytes,
        input  int unsigned budget,
        output int unsigned n_exec,
        output logic [31:0] final_pc
    );
        n_exec = 0;
        final_pc = mem_if.imem_addr;
        forever begin
            if (final_pc >= stop_bytes) break;
            if (n_exec == budget)      break;
            @(negedge clk);
            final_pc = mem_if.imem_addr;
            n_exec++;
        end
    endtask

    function automatic bit check_final_regs(input string name);
        logic [31:0] dut_regs[0:31];
        for (int i = 0; i < 32; i++)
            dut_regs[i] = u_core.u_regfile.regs[i];
        return u_scoreboard.check_regfile(name, dut_regs, ref_model.regs);
    endfunction

    task automatic record(input string name, input int seed, input bit ok);
        if (ok) pass_cnt++;
        else begin
            fail_cnt++;
            $display("  -> FAIL: %s", name);
            $display("  reproduce: make run ARGS=\"+SINGLE_SEED=%0d\"", seed);
        end
    endtask

    task automatic run_random_test(input int seed);
        rv_program p = new();
        string nm = $sformatf("random_seed_%0d", seed);
        bit ok = 1'b1;
        int unsigned prog_bytes;
        int unsigned dut_n;
        logic [31:0] dut_pc;

        p.build(seed);
        u_memory.init_mem();
        p.load_imem(u_memory.imem);
        prog_bytes = p.instrs.size() * 4;

        u_coverage.set_program_bytes(prog_bytes);

        ref_model = new();
        ref_model.run_iss(u_memory.imem, p.instrs.size(), RUN_BUDGET);

        u_monitor.clear();
        apply_reset();
        run_program(prog_bytes, RUN_BUDGET, dut_n, dut_pc);

        total_retired += ref_model.retired;
        total_txns += ref_model.expected_txns.size();
        total_static += p.instrs.size();

        ok &= u_scoreboard.check_retire(nm, dut_n, ref_model.retired, dut_pc, ref_model.pc);
        ok &= u_scoreboard.check(nm, ref_model.expected_txns, u_monitor.observed_txns);
        ok &= check_final_regs(nm);
        record(nm, seed, ok);
    endtask

    initial begin
        clk = 0;
        rst = 1;
        void'($value$plusargs("SEED_OFFSET=%0d", seed_offset));
        void'($value$plusargs("NUM_SEEDS=%0d", num_seeds));
        if ($value$plusargs("SINGLE_SEED=%0d", single_seed)) begin
            single_seed_mode = 1'b1;
            $display("RANDOM TEST: running single seed %0d", single_seed);
            run_random_test(single_seed);
        end
        else begin
            $display("RANDOM TEST: running %0d seeds", num_seeds);
            for (int s = 0; s < num_seeds; s++) begin
                $display("RANDOM TEST: running seed %0d", s);
                run_random_test(seed_offset + s);
            end
        end

        $display("========================================");
        $display("SUMMARY: %0d passed, %0d failed | total_txns=%0d, total_retired=%0d",
                 pass_cnt, fail_cnt, total_txns, total_retired);
        $display("ASSERTION FAILURES: %0d", u_assertions.fail_count);
        $display("========================================");
        if (u_assertions.fail_count != 0)
            $fatal(1, "CORE ASSERTIONS FAILED: %0d", u_assertions.fail_count);
        if (fail_cnt != 0)
            $fatal(1, "RANDOM REGRESSION FAILED: %0d/%0d", fail_cnt, pass_cnt + fail_cnt);
        if (ref_model.retired >= RUN_BUDGET) begin
            $display("WARN seed=%0d hit budget, program did not terminate (coverage suspect)", single_seed_mode ? single_seed : seed_offset + num_seeds - 1);
        end
        if (single_seed_mode) begin
            if (VACUOUS_K*total_txns < total_static)
                $display("WARN: single seed sparse in memory (txns=%0d static=%0d)",
                        total_txns, total_static);
        end
        else if (VACUOUS_K*total_txns < total_static) begin
            $fatal(1, "vacuous regression: txns=%0d static=%0d (density < 1/%0d)",
                total_txns, total_static, VACUOUS_K);
        end
        $display("ALL RANDOM TESTS PASSED");
        $finish;
    end

    always #5 clk = ~clk;

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

    rv_coverage u_coverage(mem_if.monitor);

    core_scoreboard u_scoreboard();

    core_assertions u_assertions(mem_if.monitor);
endmodule