`timescale 1ns/1ps

module core_memory_model(
    core_mem_if.mem_model mem
);
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255];

    always_ff @(posedge mem.clk ) begin
        if (mem.rst) begin 
            foreach (dmem[i]) dmem[i] <= 32'b0; 
        end
        else if (mem.dmem_write) begin
                if (mem.dmem_wstrb[0])
                    dmem[mem.dmem_addr[9:2]][7:0] <= mem.dmem_wdata[7:0];
                if (mem.dmem_wstrb[1])
                    dmem[mem.dmem_addr[9:2]][15:8] <= mem.dmem_wdata[15:8];
                if (mem.dmem_wstrb[2])
                    dmem[mem.dmem_addr[9:2]][23:16] <= mem.dmem_wdata[23:16];
                if (mem.dmem_wstrb[3])
                    dmem[mem.dmem_addr[9:2]][31:24] <= mem.dmem_wdata[31:24];
        end
    end

    task automatic init_mem();
        foreach (imem[i]) imem[i] = 32'h00000013;
    endtask

    task automatic load_hex(input string path);
        $readmemh(path, imem);
    endtask
    
    assign mem.imem_rdata = imem[mem.imem_addr[9:2]];
    assign mem.dmem_rdata = mem.dmem_read ? dmem[mem.dmem_addr[9:2]] : 32'b0;

    task automatic peek_word(
        input logic [31:0] addr,
        output logic [31:0] data
    );
        data = dmem[addr[9:2]];
    endtask
endmodule
