`timescale 1ns/1ps

import single_pkg::*;

module load_store_unit(
    input  mem_size_e mem_size,
    input  logic      load_unsigned,

    input  logic [1:0]  addr_offset,
    input  logic [31:0] store_data,
    input  logic [31:0] mem_rdata,

    output logic [31:0] mem_wdata,
    output logic [3:0]  mem_wstrb,
    output logic [31:0] load_data,
    output logic        misaligned
);
    logic [31:0] load_data_reg;

    always_comb begin
        mem_wdata = 32'bx;
        mem_wstrb = 4'b0000;
        load_data_reg = 32'bx;
        load_data = 32'bx;
        misaligned = 1'bx;

        case (mem_size)
            MEM_BYTE: begin
                mem_wdata = {24'b0, store_data[7:0]} << (addr_offset * 8);
                mem_wstrb = 4'b0001 << addr_offset;
                load_data_reg = mem_rdata >> (addr_offset * 8);
                load_data = load_unsigned ? {24'b0, load_data_reg[7:0]} : {{24{load_data_reg[7]}}, load_data_reg[7:0]};
                misaligned = 1'b0;
            end

            MEM_HALF: begin
                mem_wdata = {16'b0, store_data[15:0]} << (addr_offset * 8);
                misaligned = addr_offset[0];
                mem_wstrb = misaligned ? 4'b0000 : (4'b0011 << addr_offset);
                load_data_reg = mem_rdata >> (addr_offset * 8);
                load_data = load_unsigned ? {16'b0, load_data_reg[15:0]} : {{16{load_data_reg[15]}}, load_data_reg[15:0]};
            end

            MEM_WORD: begin
                mem_wdata = store_data;
                mem_wstrb = 4'b1111;
                load_data = mem_rdata;
                misaligned = (addr_offset != 2'b00);
            end

            default: begin
                mem_wdata = 32'bx;
                mem_wstrb = 4'b0000;
                load_data = 32'bx;
                misaligned = 1'bx;
            end
        endcase
    end

endmodule
