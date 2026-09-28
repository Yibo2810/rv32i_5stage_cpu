module pipeline_sva_bind 
import single_pkg::*; 
import pipeline_pkg::*; (
    input logic clk, rst,
    input logic [31:0] imem_addr,
    input logic load_use_hazard, mem_stall, wb_trap, halted,
    input logic ex_redirect_taken, pc_stall, ifid_flush, idex_flush, idex_valid, 
    input logic exmem_reg_write, exmem_mem_read, memwb_reg_write,
    input [31:0] exmem_rd_addr, memwb_rd_addr, idex_rs1_addr, idex_rs2_addr,
    input fwd_sel_e fwd_a_sel, fwd_b_sel,
    input idex_t    idex_q,
    input exmem_t   exmem_q,
    input memwb_t   memwb_q,
    input ifid_t    ifid_q,
    input logic     wb_retire
);
    default clocking @(posedge clk); endclocking
    default disable iff (rst);

    int failure[string];
    int hit[string];
    int unsigned fail_count = 0;

    wire lu_rs1 = uses_rs1(ifid_q.instr[6:0]) && (ifid_q.instr[19:15] == idex_q.rd_addr);
    wire lu_rs2 = uses_rs2(ifid_q.instr[6:0]) && (ifid_q.instr[24:20] == idex_q.rd_addr);
    wire ex_advance = idex_q.valid && !mem_stall && !wb_trap && !halted;
    wire ex_rs1 = uses_rs1(idex_q.instr[6:0]);
    wire ex_rs2 = uses_rs2(idex_q.instr[6:0]);
    wire redirect_taken = ex_redirect_taken && !mem_stall && !wb_trap && !halted;
    wire load_use = load_use_hazard && !mem_stall && !wb_trap && !halted;
    wire exmem_forwarding_rs1 = idex_valid && exmem_reg_write && (exmem_rd_addr != 5'd0) &&(exmem_rd_addr == idex_rs1_addr) && !exmem_mem_read;
    wire memwb_forwarding_rs1 = idex_valid && memwb_reg_write && (memwb_rd_addr != 5'd0) &&(memwb_rd_addr == idex_rs1_addr);
    wire exmem_forwarding_rs2 = idex_valid && exmem_reg_write && (exmem_rd_addr != 5'd0) &&(exmem_rd_addr == idex_rs2_addr) && !exmem_mem_read;
    wire memwb_forwarding_rs2 = idex_valid && memwb_reg_write && (memwb_rd_addr != 5'd0) &&(memwb_rd_addr == idex_rs2_addr);
    wire behind_load = idex_q.valid && exmem_q.valid && exmem_q.ctrl_m.mem_read && exmem_q.ctrl_m.reg_write && exmem_q.rd_addr != 0 &&
                        ((ex_rs1 && idex_q.rs1_addr == exmem_q.rd_addr) || (ex_rs2 && idex_q.rs2_addr == exmem_q.rd_addr));


    typedef enum {C_R, C_IALU, C_LOAD, C_STORE, C_BRANCH, C_JAL, C_JALR, C_LUI, C_AUIPC, C_OTHER} iclass_e;
    function automatic iclass_e iclass(logic [6:0] op);
        case (op)
            OPCODE_R_TYPE: return C_R;      OPCODE_I_TYPE: return C_IALU;
            OPCODE_LOAD:   return C_LOAD;   OPCODE_STORE:  return C_STORE;
            OPCODE_BRANCH: return C_BRANCH; OPCODE_JAL:    return C_JAL;
            OPCODE_JALR:   return C_JALR;   OPCODE_LUI:    return C_LUI;
            OPCODE_AUIPC:  return C_AUIPC;  default:       return C_OTHER;
        endcase
    endfunction

    typedef enum {S_NONE, S_EXM_ALU, S_EXM_MEM, S_EXM_PC4, S_MWB_ALU, S_MWB_MEM, S_MWB_PC4} fsrc_e;
    function automatic fsrc_e fsrc(fwd_sel_e sel);
        if (sel == FWD_EXMEM) 
            case (exmem_q.ctrl_m.wb_sel)  
                WB_ALU: return S_EXM_ALU; 
                WB_MEM: return S_EXM_MEM; 
                default: return S_EXM_PC4;
            endcase
        if (sel == FWD_MEMWB) 
            case (memwb_q.ctrl_wb.wb_sel) 
                WB_ALU: return S_MWB_ALU; 
                WB_MEM: return S_MWB_MEM; 
                default: return S_MWB_PC4; 
            endcase
        return S_NONE;
    endfunction

    logic redirect_blocked_q;
    always @(posedge clk) redirect_blocked_q <= rst ? 1'b0 : (ex_redirect_taken && mem_stall);

    typedef enum {K_BUBBLE, K_STORE, K_LOAD, K_CTRL, K_ALU} kill_e;
    typedef enum {O_NONE, O_FROM_ALU, O_FROM_LOAD} opsrc_e;

    function automatic opsrc_e opnd_src();
        bit a = ex_rs1 && (fwd_a_sel != FWD_NONE);
        bit b = ex_rs2 && (fwd_b_sel != FWD_NONE);
        if ((a && fsrc(fwd_a_sel) == S_MWB_MEM) || (b && fsrc(fwd_b_sel) == S_MWB_MEM)) 
            return O_FROM_LOAD;
        if (a || b) 
            return O_FROM_ALU;
        return O_NONE;
    endfunction

    function automatic void report(string name);
        failure[name]++;
        fail_count++;
        $error("[PIPELINE SVA] %s failed", name);
    endfunction

    function automatic bit uses_rs1(logic [6:0] op);
        return op inside {OPCODE_R_TYPE, OPCODE_I_TYPE, OPCODE_LOAD, OPCODE_STORE, OPCODE_BRANCH, OPCODE_JALR};
    endfunction

    function automatic bit uses_rs2(logic [6:0] op);
        return op inside {OPCODE_R_TYPE, OPCODE_STORE, OPCODE_BRANCH};
    endfunction

    redirect_valid_assert: assert property (
        redirect_taken |-> ifid_q.valid
    ) else report("redirect_valid_assert");

    pc_stall_assert: assert property (
        pc_stall |=> $stable(imem_addr)
    ) else report("pc_stall_assert");

    flush_redirect: assert property (
        redirect_taken |-> (ifid_flush == 1'b1) && (idex_flush == 1'b1)
    ) else report("flush_redirect");

    load_use_assert: assert property (
        load_use |=> !load_use_hazard
    ) else report("load_use_assert");

    forward_priority_rs1: assert property (
        fwd_a_sel == FWD_EXMEM |-> exmem_forwarding_rs1
    ) else report("forward_priority_rs1");

    forward_priority2_rs1: assert property (
        fwd_a_sel == FWD_MEMWB |-> (memwb_forwarding_rs1 && !exmem_forwarding_rs1)
    ) else report("forward_priority2_rs1"); 

    forward_priority_rs2: assert property (
        fwd_b_sel == FWD_EXMEM |-> exmem_forwarding_rs2
    ) else report("forward_priority_rs2");

    forward_priority2_rs2: assert property (
        fwd_b_sel == FWD_MEMWB |-> (memwb_forwarding_rs2 && !exmem_forwarding_rs2)
    ) else report("forward_priority2_rs2"); 

    load_instr_when_stall: assert property (!behind_load) else report("load_instr_when_stall");

    retire_once: assert property (
        wb_retire |=> !(wb_retire && ($stable(memwb_q.pc)))
    ) else report("retire_once"); 

    property retire_count;
        logic [31:0] np;
        (wb_retire && !memwb_q.exc.valid, np = memwb_q.next_pc) 
        |=> (!wb_retire)[*0:$] ##1 (wb_retire && memwb_q.pc == np);
    endproperty
    retire_check: assert property (retire_count) else report("retire_check");

    assume_jump_exmem_bubble: assert property (
        exmem_q.valid && exmem_q.ctrl_m.wb_sel == WB_PC4 |-> !idex_q.valid
    ) else report("assume_jump_exmem_bubble");

    assume_jump_memwb_bubble: assert property (
        memwb_q.valid && memwb_q.ctrl_wb.wb_sel == WB_PC4 |-> !idex_q.valid
    ) else report("assume_jump_memwb_bubble");

    //hit cover
    count_lu                    : cover property (load_use_hazard)
        hit["load_use_hazard"]++;
    count_lu_act                : cover property (load_use)
        hit["hazard_acted"]++;
    count_lu_block              : cover property (load_use_hazard && mem_stall)
        hit["load_use_hazard && mem_stall"]++;
    count_redirect              : cover property (ex_redirect_taken)
        hit["ex_redirect_taken"]++;
    count_redirect_mem_stall    : cover property (ex_redirect_taken && mem_stall)
        hit["ex_redirect_taken && mem_stall"]++;
    count_pcstall               : cover property (pc_stall)
        hit["pc_stall"]++;
    count_memstall              : cover property (mem_stall)
        hit["mem_stall"]++;
    count_jump_exmem            : cover property (exmem_q.valid && exmem_q.ctrl_m.wb_sel == WB_PC4)
        hit["jump in EX/MEM"]++;
    count_retire_normal         : cover property (wb_retire && !memwb_q.exc.valid)
        hit["retire"]++;

    covergroup cg_fwd @(posedge clk iff ex_advance);
        option.per_instance = 1;
        cp_fa: coverpoint fwd_a_sel iff (ex_rs1) { bins none = {FWD_NONE}; bins exm = {FWD_EXMEM}; bins mwb = {FWD_MEMWB};}
        cp_fb: coverpoint fwd_b_sel iff (ex_rs2) { bins none = {FWD_NONE}; bins exm = {FWD_EXMEM}; bins mwb = {FWD_MEMWB};}
        cx_fa_fb: cross cp_fa, cp_fb;

        cp_cons:  coverpoint iclass(idex_q.instr[6:0]) {
            bins r = {C_R}; 
            bins ialu = {C_IALU}; 
            bins load = {C_LOAD}; 
            bins store = {C_STORE};
            bins branch = {C_BRANCH}; 
            bins jalr = {C_JALR};
            ignore_bins no_src = {C_JAL, C_LUI, C_AUIPC, C_OTHER};
        }

        cx_fa_cons: cross cp_fa, cp_cons { ignore_bins none = binsof(cp_fa.none); }
        cx_fb_cons: cross cp_fb, cp_cons {
            ignore_bins none = binsof(cp_fb.none);
            ignore_bins no_rs2 = binsof(cp_cons.ialu) || binsof(cp_cons.load) || binsof(cp_cons.jalr);
        }

        cp_src_a: coverpoint fsrc(fwd_a_sel) iff (ex_rs1) {
            bins exm_alu = {S_EXM_ALU};
            bins mwb_alu = {S_MWB_ALU};
            bins mwb_mem = {S_MWB_MEM};
            illegal_bins exm_mem = {S_EXM_MEM};
            ignore_bins pc4 = {S_EXM_PC4, S_MWB_PC4};
            ignore_bins none = {S_NONE};
        }
    endgroup
    cg_fwd fwd_cov = new();
    
    covergroup cg_lu @(posedge clk iff load_use);
        option.per_instance = 1;
        cp_cons: coverpoint iclass(ifid_q.instr[6:0]) {
            bins r = {C_R}; 
            bins ialu = {C_IALU}; 
            bins load = {C_LOAD}; 
            bins store = {C_STORE};
            bins branch = {C_BRANCH}; 
            bins jalr = {C_JALR};
            illegal_bins no_src = {C_JAL, C_LUI, C_AUIPC, C_OTHER};
        }

        cp_opnd: coverpoint {lu_rs1, lu_rs2} {
            bins rs1 = {2'b10};
            bins rs2 = {2'b01};
            bins both = {2'b11};

            illegal_bins none = {2'b00};
        }

        cx_cons_opnd: cross cp_cons, cp_opnd {ignore_bins no_rs2 = (binsof(cp_cons.ialu) ||  binsof(cp_cons.load) ||  binsof(cp_cons.jalr)) && (binsof(cp_opnd.rs2) || binsof(cp_opnd.both));}

        cp_ld: coverpoint (idex_q.instr[14:12]) {
            bins LB = {3'b000};
            bins LH = {3'b001};
            bins LW = {3'b010};
            bins LBU = {3'b100};
            bins LHU = {3'b101};
        }

        cx_ld_cons: cross cp_ld, cp_cons;
    endgroup
    cg_lu lu_cov = new();

    covergroup cg_redir @(posedge clk iff redirect_taken);
        option.per_instance = 1;
        cp_src: coverpoint iclass(idex_q.instr[6:0]) {
            bins branch = {C_BRANCH}; 
            bins jalr = {C_JALR};
            bins jal = {C_JAL};
            illegal_bins no_src = {C_R, C_IALU, C_LOAD, C_STORE, C_LUI, C_AUIPC, C_OTHER};
        }

        cp_def: coverpoint redirect_blocked_q {
            bins now = {1'b0};
            bins defer = {1'b1};
        }
        
        cp_kill: coverpoint iclass(ifid_q.instr[6:0]) {
            bins store = {C_STORE};
            bins load = {C_LOAD};
            bins ctrl = {C_BRANCH, C_JAL, C_JALR};
            bins alu = {C_R, C_IALU, C_LUI, C_AUIPC};
            ignore_bins other = {C_OTHER};
        }

        cp_opnd: coverpoint opnd_src() {
            bins none = {O_NONE};
            bins from_alu = {O_FROM_ALU};
            bins from_load = {O_FROM_LOAD};
        }

        cx_src_def: cross cp_src, cp_def;
        cx_src_kill: cross cp_src, cp_kill;
        cx_src_opnd: cross cp_src, cp_opnd {ignore_bins jalr_src = binsof(cp_src.jal) && !binsof(cp_opnd.none);}
    endgroup
    cg_redir redir_cov = new();
    final begin
        string names[$] = '{"redirect_valid_assert", "pc_stall_assert", "flush_redirect", "load_use_assert", 
        "forward_priority_rs1", "forward_priority_rs2", "forward_priority2_rs1", "forward_priority2_rs2"
        "load_instr_when_stall", "retire_once", "retire_check", "assume_jump_exmem_bubble", "assume_jump_memwb_bubble"};

        string count[$] = '{"load_use_hazard", "hazard_acted","load_use_hazard && mem_stall",
        "ex_redirect_taken", "ex_redirect_taken && mem_stall", "pc_stall", "mem_stall",
         "jump in EX/MEM", "retire"};

        foreach (failure[k]) if (!(k inside {names})) $error("unlisted key %s", k);
        $display("");
        $display("======================== PIPELINE SVA ========================");
        foreach (names[i])
            $display("  %-26s failures = %0d", names[i], failure.exists(names[i]) ? failure[names[i]] : 0);
        $display("  %-26s failures = %0d", "TOTAL", fail_count);
        $display("------------------- antecedent hits (cycles) -------------------");
        foreach (count[i])
            $display("  %-32s %0d", count[i], hit.exists(count[i]) ? hit[count[i]] : 0);
        $display("------------------ microarchitecture coverage ------------------");
        $display("PIPE_FWD_COVERAGE   = %0.2f%%", fwd_cov.get_inst_coverage());
        $display("    fa=%0.1f fb=%0.1f fa_x_fb=%0.1f fa_x_cons=%0.1f fb_x_cons=%0.1f src_a=%0.1f",
                 fwd_cov.cp_fa.get_inst_coverage(),      fwd_cov.cp_fb.get_inst_coverage(),
                 fwd_cov.cx_fa_fb.get_inst_coverage(),   fwd_cov.cx_fa_cons.get_inst_coverage(),
                 fwd_cov.cx_fb_cons.get_inst_coverage(), fwd_cov.cp_src_a.get_inst_coverage());
        $display("PIPE_LU_COVERAGE    = %0.2f%%", lu_cov.get_inst_coverage());
        $display("    cons=%0.1f opnd=%0.1f cons_x_opnd=%0.1f ld=%0.1f ld_x_cons=%0.1f",
                 lu_cov.cp_cons.get_inst_coverage(),      lu_cov.cp_opnd.get_inst_coverage(),
                 lu_cov.cx_cons_opnd.get_inst_coverage(), lu_cov.cp_ld.get_inst_coverage(),
                 lu_cov.cx_ld_cons.get_inst_coverage());
        $display("PIPE_REDIR_COVERAGE = %0.2f%%", redir_cov.get_inst_coverage());
        $display("    src=%0.1f def=%0.1f kill=%0.1f opnd=%0.1f src_x_def=%0.1f src_x_kill=%0.1f src_x_opnd=%0.1f",
                 redir_cov.cp_src.get_inst_coverage(),      redir_cov.cp_def.get_inst_coverage(),
                 redir_cov.cp_kill.get_inst_coverage(),     redir_cov.cp_opnd.get_inst_coverage(),
                 redir_cov.cx_src_def.get_inst_coverage(),  redir_cov.cx_src_kill.get_inst_coverage(),
                 redir_cov.cx_src_opnd.get_inst_coverage());
        $display("================================================================");
    end
endmodule

bind core_5stage pipeline_sva_bind u_sva(
    .clk(clk),
    .rst(rst),
    .pc_stall(pc_stall),
    .imem_addr(imem_addr),
    .ifid_q(ifid_q),
    .idex_q(idex_q),
    .exmem_q(exmem_q),
    .memwb_q(memwb_q),
    .wb_retire(u_wb_stage.wb_retire),
    .load_use_hazard(u_hazard_unit.load_use_hazard),
    .fwd_a_sel(fwd_a_sel),
    .fwd_b_sel(fwd_b_sel),
    .ex_redirect_taken(ex_redirect_taken),
    .mem_stall(mem_stall),
    .wb_trap(wb_trap),
    .halted(halted),
    .ifid_flush(ifid_flush),
    .idex_flush(idex_flush),
    .idex_valid(u_hazard_unit.idex_valid),
    .exmem_reg_write(u_fwd.exmem_reg_write),
    .memwb_reg_write(u_fwd.memwb_reg_write),
    .exmem_rd_addr(u_fwd.exmem_rd_addr),
    .memwb_rd_addr(u_fwd.memwb_rd_addr),
    .idex_rs1_addr(u_fwd.idex_rs1_addr),
    .idex_rs2_addr(u_fwd.idex_rs2_addr),
    .exmem_mem_read(u_fwd.exmem_mem_read)
);