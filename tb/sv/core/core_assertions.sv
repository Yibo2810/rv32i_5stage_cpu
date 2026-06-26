module core_assertions (
    core_mem_if.monitor mem
);
    assert property (
        @(posedge mem.clk)
        disable iff (mem.rst)
        mem.imem_addr[1:0] == 2'b00
    );
    
    assert property (
        @(posedge mem.clk)
        disable iff (mem.rst)
        !(mem.dmem_read && mem.dmem_write)
    );

    assert property (
        @(posedge mem.clk)
        disable iff (mem.rst)
        !$isunknown({mem.dmem_read, mem.dmem_write, mem.dmem_wstrb})
    );
endmodule
