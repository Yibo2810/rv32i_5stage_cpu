`timescale 1ns/1ps

module pipeline_monitor (
    pipeline_probe_if.pipeline_monitor p
);
    import pipeline_verif_pkg::*;
    import single_pkg::*;

    int unsigned trap_count;
    exc_cause_e  trap_cause_q;
    logic [31:0] trap_pc_q;

    core_mem_txn_t observed_txns[$];

    core_mem_txn_t pend;
    logic          pend_v;

    commit_t observed_commits[$];

    task automatic clear();
        observed_txns.delete();
        observed_commits.delete();
        pend_v = 1'b0;
        trap_count = 0;
    endtask

    always @(p.cb) begin
        if (p.cb.rst) begin
            pend_v = 1'b0;
        end else begin
            if (p.cb.dmem_rsp_valid && p.cb.dmem_rsp_ready && pend_v) begin
                pend.rdata = p.cb.dmem_rsp_rdata;
                observed_txns.push_back(pend);
                pend_v = 1'b0;
            end

            if (p.cb.dmem_req_valid && p.cb.dmem_req_ready) begin
                pend.pc       = p.cb.mem_pc;
                pend.instr    = p.cb.mem_instr;
                pend.is_read  = !p.cb.dmem_req_write;
                pend.is_write = p.cb.dmem_req_write;
                pend.addr     = p.cb.dmem_req_addr;
                pend.wdata    = p.cb.dmem_req_wdata;
                pend.wstrb    = p.cb.dmem_req_wstrb;
                pend.rdata    = 32'b0;
                pend_v        = 1'b1;
            end
        end
    end

    always @(p.cb) begin
        if (!p.cb.rst && p.cb.retire && !p.cb.retire_exc) begin
            commit_t c;
            c.pc      = p.cb.retire_pc;
            c.instr   = p.cb.retire_instr;
            c.next_pc = p.cb.retire_next_pc;
            c.rd_we   = p.cb.rd_we;
            c.rd_addr = p.cb.rd_addr;
            c.rd_data = p.cb.rd_data;
            observed_commits.push_back(c);
        end
    end

    always @(p.cb) begin
        if (!p.cb.rst && p.cb.trap_valid) begin
            trap_count++;
            trap_cause_q = p.cb.trap_cause;
            trap_pc_q    = p.cb.trap_pc;
        end
    end
endmodule