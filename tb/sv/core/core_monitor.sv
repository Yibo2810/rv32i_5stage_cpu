`timescale 1ns/1ps


module core_monitor (
    core_mem_if.monitor mem
);
    import core_verif_pkg::*;

    core_mem_txn_t observed_txns[$];

    task automatic clear();
        observed_txns.delete();
    endtask

    always @(mem.cb) begin
        if (!mem.cb.rst && (mem.cb.dmem_read || mem.cb.dmem_write)) begin
            core_mem_txn_t  txn;
            txn.pc      = mem.cb.imem_addr;
            txn.instr   = mem.cb.imem_rdata;
            txn.is_read = mem.cb.dmem_read;
            txn.is_write= mem.cb.dmem_write;
            txn.addr    = mem.cb.dmem_addr;
            txn.wdata   = mem.cb.dmem_wdata;
            txn.wstrb   = mem.cb.dmem_wstrb;
            txn.rdata   = mem.cb.dmem_rdata;
            observed_txns.push_back(txn);
        end
    end
endmodule
