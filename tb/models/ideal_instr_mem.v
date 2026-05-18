module instr_mem (
    input  [31:0] imem_addr,
    output [31:0] imem_rdata
);
    reg [31:0] imem [0:255];
    reg [1023:0] hex_file;
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            imem [i] = 32'h00000013;
        end

        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("ERROR: missing +HEX=<program.hex>");
            $finish;
        end

        $readmemh(hex_file, imem);
    end

    assign imem_rdata = imem[imem_addr[9:2]];
endmodule