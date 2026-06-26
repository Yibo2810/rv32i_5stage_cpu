`timescale 1ns/1ps

package core_test_db_pkg;
    import core_verif_pkg::*;

    task automatic start_test(
        ref core_test_case_t t,
        input string name,
        input string hex_path,
        input string expected_path,
        input int unsigned max_cycles
        );
        t.expected_txns.delete();
        t.expected_sigs.delete();
        t.name = name;
        t.hex_path = hex_path;
        t.expected_path = expected_path;
        t.max_cycles = max_cycles;
    endtask

    task automatic build_core_test_list(ref core_test_case_t tests[$]);
        core_test_case_t t;

        tests.delete();

        start_test(
            t,
            "x0_test",
            "programs/hex/x0_test.hex",
            "programs/expected/x0_test.expected",
            30
        );
        tests.push_back(t);

        start_test(
            t,
            "alu_itype_test",
            "programs/hex/alu_itype_test.hex",
            "programs/expected/alu_itype_test.expected",
            30
        );
        tests.push_back(t);

        start_test(
            t,
            "alu_rtype_test",
            "programs/hex/alu_rtype_test.hex",
            "programs/expected/alu_rtype_test.expected",
            30
        );
        tests.push_back(t);

        start_test(
            t,
            "load_store_width_test",
            "programs/hex/load_store_width_test.hex",
            "programs/expected/load_store_width_test.expected",
            30
        );
        tests.push_back(t);

        start_test(
            t,
            "branch_matrix_test",
            "programs/hex/branch_matrix_test.hex",
            "programs/expected/branch_matrix_test.expected",
            200
        );
        tests.push_back(t);

        start_test(
            t,
            "jump_u_type_test",
            "programs/hex/jump_u_type_test.hex",
            "programs/expected/jump_u_type_test.expected",
            200
        );
        tests.push_back(t);
    endtask
endpackage
