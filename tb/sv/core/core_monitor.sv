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
    
    task automatic report(input string test_name);
        $display("MONITOR: %s captured %0d transactions",test_name,observed_txns.size());

        foreach (observed_txns[i]) begin
            if (observed_txns[i].is_write) begin
                $display("TXN[%0d] WRITE: pc=%08h addr=%08h wdata=%08h wstrb=%08h",
                        i,
                        observed_txns[i].pc,
                        observed_txns[i].addr,
                        observed_txns[i].wdata,
                        observed_txns[i].wstrb
                        );
            end
            else if (observed_txns[i].is_read) begin
                $display("TXN[%0d] READ: pc=%08h addr=%08h rdata=%08h",
                        i,
                        observed_txns[i].pc,
                        observed_txns[i].addr,
                        observed_txns[i].rdata
                        );
            end
        end
    endtask
endmodule
