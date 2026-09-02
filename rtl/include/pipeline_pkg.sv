package pipeline_pkg;
    import single_pkg::*;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] pc_plus_4;
        logic [31:0] instr;
    } ifid_t;

    typedef struct packed {
        logic          mem_write;
        logic          mem_read;
        logic          reg_write;
        logic          alu_sel_b;
        wb_sel_e       wb_sel;
        logic          branch;
        alu_ctrl_e     alu_ctrl;
        //imm_sel_e      imm_sel;  only used to imm_gen, there is no need to transform to the next stage.
        logic          illegal_instr;
        logic          branch_on_zero;
        mem_size_e     mem_size;
        logic          load_unsigned;
        logic          jump_and_link;
        alu_src_a_sel_e alu_src_a_sel;
        pc_target_sel_e pc_target_sel;
        logic          sys_ecall;
        logic          sys_ebreak;
    } idex_ctrl_t;
    
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] pc_plus_4;
        logic [31:0] instr;

        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [4:0]  rd_addr;
        logic [31:0] imm;

        idex_ctrl_t  ctrl;
    } idex_t;
    
    typedef struct packed {
        logic        mem_read;
        logic        mem_write;
        mem_size_e   mem_size;
        logic        load_unsigned;
        logic        reg_write;
        wb_sel_e     wb_sel;
        logic        illegal_instr;
        logic        sys_ecall;
        logic        sys_ebreak;
    } exmem_ctrl_t;

  typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] next_pc;
        logic [31:0] alu_result;
        logic [31:0] store_data;
        logic [31:0] pc_plus_4;
        logic [4:0]  rd_addr;
        exmem_ctrl_t ctrl_m;
    } exmem_t;

  typedef struct packed {
        logic        reg_write;
        wb_sel_e     wb_sel;
        logic        illegal_instr;
        logic        mem_fault;
        logic        sys_ecall;
        logic        sys_ebreak;
    } memwb_ctrl_t;

  typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] next_pc;
        logic [31:0] alu_result;
        logic [31:0] load_data;
        logic [31:0] pc_plus_4;
        logic [4:0]  rd_addr;
        memwb_ctrl_t ctrl_wb;
    } memwb_t;

  typedef enum logic [1:0] { 
    FWD_NONE = 2'b00,
    FWD_EXMEM = 2'b01,
    FWD_MEMWB = 2'b10
   } fwd_sel_e;
endpackage