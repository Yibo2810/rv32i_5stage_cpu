`timescale 1ps/1ps

package core_verif_pkg;

    typedef enum logic [3:0] {
        CORE_TEST_ADD,
        CORE_TEST_SUB,
        CORE_TEST_LOAD_STORE,
        CORE_TEST_BRANCH,
        CORE_TEST_X0,
        CORE_TEST_ILLEGAL_INSTR
    } core_test_id_e;

    typedef enum logic [1:0] {
        CHECK_DMEM_WORD,
        CHECK_NO_DMEM_WRITE,
        CHECK_PC_VALUE
    } core_check_kind_e;

    typedef struct {
        core_test_id_e       id;
        string               name;
        int unsigned         max_cycles;
        core_check_kind_e    check_kind;
        int unsigned         expected_dmem_word_addr;
        logic [31:0]         expected_dmem_word_value;
        string               hex_path;
    } core_test_cfg_t;

endpackage
