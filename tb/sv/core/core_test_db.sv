`timescale 1ns/1ps

package core_test_db_pkg;
    import core_verif_pkg::*;

    task automatic start_test(
        ref core_test_case_t t,
        input string name,
        input string hex_path,
        input int unsigned max_cycles
        );
        t.expected_txns.delete();
        t.expected_sigs.delete();
        t.name = name;
        t.hex_path = hex_path;
        t.max_cycles = max_cycles;
    endtask

    task automatic add_write(
        ref core_test_case_t t,
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0]  wstrb
        );
        t.expected_txns.push_back('{
            kind: MEM_EXPECT_WRITE,
            addr: addr,
            data: data,
            wstrb: wstrb
        });
    endtask

    task automatic add_read(
        ref core_test_case_t t, 
        input logic [31:0] addr, 
        input logic [31:0] data
        );
        t.expected_txns.push_back('{
            kind: MEM_EXPECT_READ, 
            addr: addr, 
            data: data, 
            wstrb: 4'b0000
        });
    endtask

    task automatic add_sig(
        ref core_test_case_t t,
        input logic [31:0] addr,
        input logic [31:0] data
        );
        t.expected_sigs.push_back('{
            addr: addr,
            data: data
        });
    endtask

    task automatic add_sig_store(
        ref core_test_case_t t, 
        input logic [31:0] addr, 
        input logic [31:0] data,
        input logic [3:0]  wstrb
        );
        add_write(t, addr, data, wstrb);
        add_sig(t, addr, data);
    endtask

    task automatic build_core_test_list(ref core_test_case_t tests[$]);
        core_test_case_t t;

        tests.delete();

        start_test(t, "add_test", "programs/hex/add_test.hex", 20);
        add_write(t, 32'd0, 32'd12, 4'b1111);
        add_sig  (t, 32'd0, 32'd12);
        tests.push_back(t);

        start_test(t, "sub_test", "programs/hex/sub_test.hex", 20);
        add_write(t, 32'd0, 32'd5, 4'b1111);
        add_sig  (t, 32'd0, 32'd5);
        tests.push_back(t);

        start_test(t, "load_store_test", "programs/hex/load_store_test.hex", 20);
        add_sig_store(t, 32'd0, 32'd42, 4'b1111);
        add_read(t, 32'd0, 32'd42);
        add_sig(t, 32'd0, 32'd42);
        add_sig_store(t, 32'd4, 32'd42, 4'b1111);
        tests.push_back(t);

        start_test(t, "x0_test", "programs/hex/x0_test.hex", 20);
        add_sig_store(t, 32'd0, 32'd5, 4'b1111);
        add_sig_store(t, 32'd4, 32'd0, 4'b1111);
        add_sig_store(t, 32'd8, 32'd3, 4'b1111);
        add_sig_store(t, 32'd12, 32'd5, 4'b1111);
        add_read(t, 32'd4, 32'd0);
        add_sig(t, 32'd4, 32'd0);
        add_sig_store(t, 32'd16, 32'd0, 4'b1111);
        add_read(t, 32'd0, 32'd5);
        add_sig(t, 32'd0, 32'd5);
        add_sig_store(t, 32'd20, 32'd5, 4'b1111);
        tests.push_back(t);
    endtask
endpackage
