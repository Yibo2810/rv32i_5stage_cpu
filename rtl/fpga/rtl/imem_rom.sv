`timescale 1ns/1ps
module imem_rom #(
    parameter int DEPTH = 256,
    parameter string INIT_FILE = ""
) (
    input logic [31:0] addr,
    output logic [31:0] rdata
);
    localparam int ADDR_W = $clog2(DEPTH);
    logic [ADDR_W-1:0] idx;

    (* rom_style = "distributed" *)
    logic [31:0] rom [0:DEPTH-1];

    assign idx = addr[ADDR_W+1:2];
    assign rdata = rom[idx];

    initial begin
        $readmemh(INIT_FILE, rom);
    end
endmodule