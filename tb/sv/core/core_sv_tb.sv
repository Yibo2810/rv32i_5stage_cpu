`timescale 1ns/1ps

import core_verif_pkg::*;
import core_test_db_pkg::*;
module core_sv_tb;

    logic clk;
    logic rst;
    core_test_case_t tests[$];

    task automatic apply_reset();
        rst = 1'b1;
        repeat (2) @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
    endtask
    
    task automatic run_cycles(input int unsigned cycles);
        repeat (cycles) begin
            @(mem_if.cb);
            @(negedge clk);
        end
    endtask

    task automatic check_signatures(input core_test_case_t t);
        logic [31:0] actual_word;

        foreach (t.expected_sigs[i]) begin
            u_memory.peek_word(t.expected_sigs[i].addr, actual_word);
            u_scoreboard.check_signature_word(
                t.name, t.expected_sigs[i].addr, t.expected_sigs[i].data, actual_word
            );
        end
    endtask

    task automatic run_test(input core_test_case_t t);
        $display("RUN: %s", t.name);

        u_memory.init_mem();
        u_memory.load_hex(t.hex_path);

        u_monitor.clear();

        apply_reset();
        run_cycles(t.max_cycles);

        if (t.expected_txns.size() != 0)
            u_scoreboard.check(t.name, t.expected_txns, u_monitor.observed_txns);

        check_signatures(t);

    endtask
    
    always #5 clk = ~clk;

    initial begin
    clk = 0;
    rst = 1;

    build_core_test_list(tests);

    foreach (tests[i])
        run_test(tests[i]);

    $display("ALL CORE SV TESTS PASSED");
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
        .dmem_rdata(mem_if.dmem_rdata)
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