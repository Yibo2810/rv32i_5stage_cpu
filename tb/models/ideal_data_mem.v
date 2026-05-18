module data_mem (
    input  clk,
    input  rst,

    input dmem_read,
    input dmem_write,

    input  [31:0] dmem_addr,
    input  [31:0] dmem_wdata,
    output [31:0] dmem_rdata
);
    reg [31:0] dmem [0:255];
    integer i;
    assign dmem_rdata = dmem[dmem_addr[9:2]];

    always @(posedge clk ) begin
        if (rst) begin
            for (i = 0; i < 256; i = i + 1) begin
                dmem[i] <= 32'b0;
            end
        end
        else if (dmem_write) begin
            dmem[dmem_addr[31:2]] <= dmem_wdata;
        end
    end
endmodule