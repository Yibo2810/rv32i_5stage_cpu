`timescale 1ns/1ps

module pipeline_tb;
    import single_pkg::*;
    import pipeline_verif_pkg::*;
    import pl_random_pkg::*;

    logic clk = 1'b0;
    logic rst = 1'b1;
    pl_ref_model ref_model;

    localparam int unsigned MAX_CYCLES = 4000;
    int unsigned pass_cnt = 0;
    int unsigned fail_cnt = 0;
    int unsigned num_seeds = 30;
    int unsigned total_txns = 0;
    int unsigned total_retired = 0;
    int unsigned total_static = 0;
    int          single_seed;
    int seed_offset = 0;
    int unsigned cycles;
    string       hex;
    bit          timeout;

    bit single_seed_mode = 1'b0;
    localparam int VACUOUS_K = 12;
    localparam int unsigned RUN_BUDGET = 2000;
    always #5 clk = ~clk;

    assign pif.mem_pc         = u_core.exmem_q.pc;
    assign pif.mem_instr      = u_core.exmem_q.instr;
    assign pif.retire         = u_core.u_wb_stage.wb_retire;
    assign pif.retire_exc     = u_core.memwb_q.exc.valid;
    assign pif.retire_pc      = u_core.memwb_q.pc;
    assign pif.retire_instr   = u_core.memwb_q.instr;
    assign pif.retire_next_pc = u_core.memwb_q.next_pc;
    assign pif.rd_we          = u_core.wb_w_en;
    assign pif.rd_addr        = u_core.wb_rd_addr;
    assign pif.rd_data        = u_core.wb_rd_data;

    task automatic apply_reset();
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic run_until_halt(
        input int unsigned max_cycles,
        output int unsigned cycles,
        output bit timeout
    );
        cycles = 0;
        timeout = 1'b0;
        while (pif.halted !== 1'b1) begin
            if (cycles == max_cycles) begin
                timeout = 1'b1;
                return;
            end
            @(negedge clk);
            cycles++;
        end
    endtask
    
    function automatic logic [31:0] lane_mask(input logic [3:0] wstrb);
        return {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};
    endfunction

    function automatic bit check_final_regs(input string name);
        logic [31:0] dut_regs[0:31];
        for (int i = 0; i < 32; i++)
            dut_regs[i] = u_core.u_id_stage.u_regfile.regs[i];
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

    task automatic dump_result(input string hex, input int unsigned cycles, input bit timeout);
        $display("---- %s", hex);
        foreach (u_monitor.observed_commits[i]) begin
            commit_t c = u_monitor.observed_commits[i];
            if (c.rd_we)
                $display("COMMIT pc=%08h instr=%08h next=%08h x%0d=%08h", c.pc, c.instr, c.next_pc, c.rd_addr, c.rd_data);
            else
                $display("COMMIT pc=%08h instr=%08h next=%08h", c.pc, c.instr, c.next_pc);
        end
        foreach (u_monitor.observed_txns[i]) begin
            core_mem_txn_t t = u_monitor.observed_txns[i];
            if (t.is_write)
                $display("TXN W %08h %08h %04b", t.addr, t.wdata & lane_mask(t.wstrb), t.wstrb);
            else
                $display("TXN R %08h %08h %04b", t.addr, t.rdata, 4'b0000);
        end
        for (int r = 1; r < 32; r++)
            if (u_core.u_id_stage.u_regfile.regs[r] != 32'b0)
                $display("REG x%0d = %08h", r, u_core.u_id_stage.u_regfile.regs[r]);
        $display("SUMMARY cycles=%0d timeout=%0d traps=%0d trap_cause=%s trap_pc=%08h commits=%0d txns=%0d",
                 cycles, timeout, u_monitor.trap_count, u_monitor.trap_cause_q.name(), u_monitor.trap_pc_q,
                 u_monitor.observed_commits.size(), u_monitor.observed_txns.size());
    endtask

    task automatic run_random_test(input int seed);
        pl_program p = new();
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
        for (int i = 0; i < 256; i++)
            ref_model.dmem[i] = u_memory.peek_dmem(i*4);
        ref_model.run_iss(u_memory.imem, RUN_BUDGET);

        u_monitor.clear();
        apply_reset();
        run_until_halt(MAX_CYCLES, cycles, timeout);

        total_retired += ref_model.retired;
        total_txns += ref_model.expected_txns.size();
        total_static += p.instrs.size();

        ok &= u_scoreboard.check_retire(nm, dut_n, ref_model.retired, dut_pc, ref_model.pc);
        ok &= u_scoreboard.check(nm, ref_model.expected_txns, u_monitor.observed_txns);
        ok &= u_scoreboard.check_commits(nm, u_monitor.observed_commits, ref_model.commits);
        ok &= check_final_regs(nm);
        record(nm, seed, ok);
    endtask

    initial begin

        if (!$value$plusargs("HEX=%s", hex))
            hex = "programs/hex/load_store_width_test.hex";

        u_memory.load_hex(hex);
        u_monitor.clear();
        apply_reset();
        run_until_halt(MAX_CYCLES, cycles, timeout);
        repeat (2) @(negedge clk);       // when ebreak, run 2 cycles to see the state after break
        dump_result(hex, cycles, timeout);

        if (!timeout && u_monitor.trap_count == 1 && u_monitor.trap_cause_q == EXC_BREAKPOINT)
            $display("BRINGUP DONE: halted on ebreak (not yet checked against a reference)");
        else
            $display("BRINGUP FAIL: timeout=%0d traps=%0d cause=%s",
                     timeout, u_monitor.trap_count, u_monitor.trap_cause_q.name());
        $finish;
    end

    pipeline_probe_if pif (
        .clk(clk), 
        .rst(rst)
    );
    
    pipeline_memory  u_memory (.p(pif));
    pipeline_monitor u_monitor (.p(pif));
    pl_coverage      u_coverage(pif.pipeline_monitor);
    pipeline_scoreboard u_scoreboard();
    pipeline_assertions u_assertions (pif.pipeline_monitor);

    core_5stage u_core (
        .clk           (clk),
        .rst           (rst),
        .imem_addr     (pif.imem_addr),
        .imem_rdata    (pif.imem_rdata),
        .dmem_req_valid(pif.dmem_req_valid),
        .dmem_req_ready(pif.dmem_req_ready),
        .dmem_req_write(pif.dmem_req_write),
        .dmem_req_addr (pif.dmem_req_addr),
        .dmem_req_wdata(pif.dmem_req_wdata),
        .dmem_req_wstrb(pif.dmem_req_wstrb),
        .dmem_rsp_valid(pif.dmem_rsp_valid),
        .dmem_rsp_ready(pif.dmem_rsp_ready),
        .dmem_rsp_rdata(pif.dmem_rsp_rdata),
        .trap_valid    (pif.trap_valid),
        .trap_cause    (pif.trap_cause),
        .trap_pc       (pif.trap_pc),
        .halted        (pif.halted)
    );
endmodule
