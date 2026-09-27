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
    input logic     wb_retire
);
    default clocking @(posedge clk); endclocking
    default disable iff (rst);

    int failure[string];
    int hit[string];
    int unsigned fail_count = 0;

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

    wire redirect_taken = ex_redirect_taken && !mem_stall && !wb_trap && !halted;
    wire load_use = load_use_hazard && !mem_stall && !wb_trap && !halted;
    wire exmem_forwarding_rs1 = idex_valid && exmem_reg_write && (exmem_rd_addr != 5'd0) &&(exmem_rd_addr == idex_rs1_addr) && !exmem_mem_read;
    wire memwb_forwarding_rs1 = idex_valid && memwb_reg_write && (memwb_rd_addr != 5'd0) &&(memwb_rd_addr == idex_rs1_addr);
    wire exmem_forwarding_rs2 = idex_valid && exmem_reg_write && (exmem_rd_addr != 5'd0) &&(exmem_rd_addr == idex_rs2_addr) && !exmem_mem_read;
    wire memwb_forwarding_rs2 = idex_valid && memwb_reg_write && (memwb_rd_addr != 5'd0) &&(memwb_rd_addr == idex_rs2_addr);
    wire behind_load = idex_q.valid && exmem_q.valid && exmem_q.ctrl_m.mem_read && exmem_q.ctrl_m.reg_write && exmem_q.rd_addr != 0 &&
                        ( (uses_rs1(idex_q.instr[6:0]) && idex_q.rs1_addr == exmem_q.rd_addr) || (uses_rs2(idex_q.instr[6:0]) && idex_q.rs2_addr == exmem_q.rd_addr) );

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
    count_fwda_exmem            : cover property (fwd_a_sel == FWD_EXMEM)
        hit["fwd_a=EXMEM"]++;
    count_fwda_memwb            : cover property (fwd_a_sel == FWD_MEMWB)
        hit["fwd_a=MEMWB"]++;
    count_fwdb_exmem            : cover property (fwd_b_sel == FWD_EXMEM)
        hit["fwd_b=EXMEM"]++;
    count_fwdb_memwb            : cover property (fwd_b_sel == FWD_MEMWB)
        hit["fwd_b=MEMWB"]++;
    count_fwda_fwdb             : cover property (fwd_a_sel == FWD_EXMEM && fwd_b_sel == FWD_MEMWB)
        hit["fwd_a=EXMEM & fwd_b=MEMWB"]++;
    count_fwdb_fwda             : cover property (fwd_a_sel == FWD_MEMWB && fwd_b_sel == FWD_EXMEM)
        hit["fwd_a=MEMWB & fwd_b=EXMEM"]++;
    count_fwda_wb_pc4           : cover property (fwd_a_sel == FWD_EXMEM && exmem_q.ctrl_m.wb_sel == WB_PC4)
        hit["fwd_a=EXMEM from WB_PC4"]++;
    count_retire_normal         : cover property (wb_retire && !memwb_q.exc.valid)
        hit["retire"]++;
    
    final begin
        string names[$] = '{"pc_stall_assert", "flush_redirect", "load_use_assert", 
        "redirect_load_priority", "forward_priority_rs1", "forward_priority_rs2", 
        "load_instr_when_stall", "retire_once", "retire_check"};

        string count[$] = '{"load_use_hazard", "hazard_acted","load_use_hazard && mem_stall",
        "ex_redirect_taken", "ex_redirect_taken && mem_stall", "pc_stall", "mem_stall",
        "fwd_a=EXMEM", "fwd_a=MEMWB", "fwd_b=EXMEM", "fwd_b=MEMWB", "fwd_a=EXMEM & fwd_b=MEMWB",
        "fwd_a=MEMWB & fwd_b=EXMEM", "fwd_a=EXMEM from WB_PC4", "retire"};

        foreach (failure[k]) if (!(k inside {names})) $error("unlisted key %s", k);
        $display("");
        $display("==================== SVA RESULT ====================");
        foreach (names[i]) $display("  %-12s  failures = %0d", names[i], failure.exists(names[i]) ? failure[names[i]] : 0);
        $display("---------------- antecedent hit counts (cycles) --------------");
        foreach (count[i])    $display("  %-30s %0d", count[i], hit.exists(count[i]) ? hit[count[i]] : 0);
        $display("=============================================================");

    end
endmodule

bind core_5stage pipeline_sva_bind u_sva(
    .clk(clk),
    .rst(rst),
    .pc_stall(pc_stall),
    .imem_addr(imem_addr),
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