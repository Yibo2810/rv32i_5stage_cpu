`timescale 1ns/1ps

import core_verif_pkg::*;

module core_sv_tb;

    logic clk;
    logic rst;
    core_test_cfg_t tests[$];
    logic [31:0] actual_value;

    task automatic apply_reset();
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic run_cycles(
        input int unsigned cycles
    );
        repeat (cycles) begin
            @(posedge clk);
            #1;
            $display("pc=%h instr=%h dmem_we=%b dmem_addr=%h dmem_wdata=%h dmem_wstrb=%h",
                mem_if.imem_addr,
                mem_if.imem_rdata,
                mem_if.dmem_write,
                mem_if.dmem_addr,
                mem_if.dmem_wdata,
                mem_if.dmem_wstrb
            );
        end
    endtask
    
    task automatic build_test_list();
        tests.push_back('{
            id: CORE_TEST_ADD,
            name: "add_test",
            hex_path: "programs/hex/add_test.hex",
            max_cycles: 20,
            check_kind: CHECK_DMEM_WORD,
            expected_dmem_word_addr: 0,
            expected_dmem_word_value: 32'h0000000c
        });

        tests.push_back('{
            id: CORE_TEST_SUB,
            name: "sub_test",
            hex_path: "programs/hex/sub_test.hex",
            max_cycles: 20,
            check_kind: CHECK_DMEM_WORD,
            expected_dmem_word_addr: 0,
            expected_dmem_word_value: 32'h00000005
        });

        tests.push_back('{
            id: CORE_TEST_BRANCH,
            name: "branch_test",
            hex_path: "programs/hex/branch_test.hex",
            max_cycles: 20,
            check_kind: CHECK_DMEM_WORD,
            expected_dmem_word_addr: 0,
            expected_dmem_word_value: 32'h00000001
        });

        tests.push_back('{
            id: CORE_TEST_LOAD_STORE,
            name: "load_store_test",
            hex_path: "programs/hex/load_store_test.hex",
            max_cycles: 20,
            check_kind: CHECK_DMEM_WORD,
            expected_dmem_word_addr: 1,
            expected_dmem_word_value: 32'h0000002a
        });
    endtask
    
    task automatic check_result(input core_test_cfg_t t);
        case (t.check_kind)
            CHECK_DMEM_WORD: begin
                actual_value = u_memory.dmem[t.expected_dmem_word_addr];

                if (actual_value !== t.expected_dmem_word_value) begin
                    $display("FAIL: %s expected dmem[%0d]=%08h, got %08h",
                    t.name,
                    t.expected_dmem_word_addr,
                    t.expected_dmem_word_value,
                    actual_value
                    );
                    $fatal(1);
                end
            end

            default: begin
                $display("ERROR: unsupported check kind");
                $fatal(1);
            end
        endcase
    endtask

    task automatic run_test(input core_test_cfg_t t);
        $display("RUN: %s", t.name);

        u_memory.init_mem();
        u_memory.load_hex(t.hex_path);
        u_monitor.clear();
        apply_reset();
        run_cycles(t.max_cycles);
        u_monitor.report(t.name);
        check_result(t);

        $display("PASS: %s", t.name);
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
endmodule