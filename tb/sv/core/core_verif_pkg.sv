`timescale 1ps/1ps

package core_verif_pkg;

    typedef struct {
        logic [31:0] pc;
        logic [31:0] instr;
        logic        is_read;
        logic        is_write;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0]  wstrb;
        logic [31:0] rdata;
    } core_mem_txn_t;

    typedef enum logic { 
        MEM_EXPECT_READ,
        MEM_EXPECT_WRITE
    } core_mem_expect_kind_e;

    typedef struct {
        core_mem_expect_kind_e kind;
        logic [31:0]           addr;
        logic [31:0]           data;
        logic [3:0]            wstrb;
    } core_mem_expect_t;

    typedef struct {
        string          name;
        string          hex_path;
        int unsigned    max_cycles;
        core_mem_expect_t expected_txns[$];
    } core_test_case_t;

endpackage
