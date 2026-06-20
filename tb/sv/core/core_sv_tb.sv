`timescale 1ns/1ps

import core_verif_pkg::*;

module core_sv_tb;

    logic clk;
    logic rst;
    core_test_case_t tests[$];

    task automatic apply_reset();
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
    endtask
    
    task automatic run_cycles(input int unsigned cycles);
        repeat (cycles) begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic build_test_list();
        core_test_case_t t;
        tests.delete();

        t.expected_txns.delete();
        t.name      =   "add_test";
        t.hex_path  =   "programs/hex/add_test.hex";
        t.max_cycles  =    20;
        t.expected_txns.push_back('{
            kind:   MEM_EXPECT_WRITE,
            addr:   32'd0,
            data:   32'd12,
            wstrb:  4'b1111
        });
        tests.push_back(t);
        
        t.expected_txns.delete();
        t.name       = "sub_test";
        t.hex_path   = "programs/hex/sub_test.hex";
        t.max_cycles = 20;
        t.expected_txns.push_back('{
            kind:  MEM_EXPECT_WRITE,
            addr:  32'd0,
            data:  32'd5,
            wstrb: 4'b1111
        });
        tests.push_back(t);

        t.expected_txns.delete();
        t.name       = "branch_test";
        t.hex_path   = "programs/hex/branch_test.hex";
        t.max_cycles = 20;
        t.expected_txns.push_back('{
            kind:  MEM_EXPECT_WRITE,
            addr:  32'd0,
            data:  32'd1,
            wstrb: 4'b1111
        });
        tests.push_back(t);

        t.expected_txns.delete();
        t.name       = "load_store_test";
        t.hex_path   = "programs/hex/load_store_test.hex";
        t.max_cycles = 20;
        t.expected_txns.push_back('{
            kind:  MEM_EXPECT_WRITE,
            addr:  32'd0,
            data:  32'd42,
            wstrb: 4'b1111
        });
        t.expected_txns.push_back('{
            kind:  MEM_EXPECT_READ,
            addr:  32'd0,
            data:  32'd42,
            wstrb: 4'b0000
        });
        t.expected_txns.push_back('{
            kind:  MEM_EXPECT_WRITE,
            addr:  32'd4,
            data:  32'd42,
            wstrb: 4'b1111
        });
        tests.push_back(t);
    endtask

    task automatic run_test(input core_test_case_t t);
        $display("RUN: %s", t.name);

        u_memory.init_mem();
        u_memory.load_hex(t.hex_path);

        u_monitor.clear();

        apply_reset();
        run_cycles(t.max_cycles);
        u_scoreboard.check(
            t.name,
            t.expected_txns,
            u_monitor.observed_txns
        );

    endtask



    always #5 clk = ~clk;

initial begin
  clk = 0;
  rst = 1;

  build_test_list();

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
endmodule