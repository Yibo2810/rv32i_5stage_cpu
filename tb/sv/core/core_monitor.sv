`timescale 1ns/1ps


module core_monitor (
    core_mem_if.monitor mem
);
    import core_verif_pkg::*;

    core_mem_txn_t observed_txns[$];

    task automatic clear();
        observed_txns.delete();
    endtask

    always @(posedge mem.clk) begin
        if (!mem.rst && (mem.dmem_read || mem.dmem_write)) begin
            core_mem_txn_t  txn;
            txn.pc      = mem.imem_addr;
            txn.instr   = mem.imem_rdata;
            txn.is_read = mem.dmem_read;
            txn.is_write= mem.dmem_write;
            txn.addr    = mem.dmem_addr;
            txn.wdata   = mem.dmem_wdata;
            txn.wstrb   = mem.dmem_wstrb;
            txn.rdata   = mem.dmem_rdata;
            observed_txns.push_back(txn);
        end
    end
endmodule
