module data_mem (
    input  clk,

    input dmem_read,
    input dmem_write,

    input  [31:0] dmem_addr,
    input  [31:0] dmem_wdata,
    input  [3:0]  dmem_wstrb,
    output [31:0] dmem_rdata
);
    reg [31:0] dmem [0:255];
    integer i;
    assign dmem_rdata = dmem_read ? dmem[dmem_addr[9:2]] : 32'b0;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            dmem[i] = 32'b0;
        end
    end

    always @(posedge clk ) begin
        if (dmem_write) begin
            if (dmem_wstrb[0])
                dmem[dmem_addr[9:2]][7:0] <= dmem_wdata[7:0];
            if (dmem_wstrb[1])
                dmem[dmem_addr[9:2]][15:8] <= dmem_wdata[15:8];
            if (dmem_wstrb[2])
                dmem[dmem_addr[9:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3])
                dmem[dmem_addr[9:2]][31:24] <= dmem_wdata[31:24];
        end
    end
endmodule
