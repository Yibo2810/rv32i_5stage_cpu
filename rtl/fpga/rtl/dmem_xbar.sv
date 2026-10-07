`timescale 1ns/1ps
// Address map lives in fpga_sys parameters (RAM_BASE/RAM_AW/MMIO_BASE/MMIO_AW).
// Each region is 2**AW bytes and its base must be aligned to that size, so the
// decode is a single compare of addr[31:AW]. sys_ram depth = 1 << (RAM_AW-2).
module dmem_xbar #(
    parameter logic [31:0] RAM_BASE  = 32'h8000_0000,
    parameter int          RAM_AW    = 16,          // 64 KB
    parameter logic [31:0] MMIO_BASE = 32'h1000_0000,
    parameter int          MMIO_AW   = 12           // 4 KB
) (
    input logic rst, clk,
    // Core
    // Core -> XBAR request
    input   logic        dmem_req_valid,
    output  logic        dmem_req_ready,
    input   logic        dmem_req_write,
    input   logic [31:0] dmem_req_addr,
    input   logic [31:0] dmem_req_wdata,
    input   logic [3:0]  dmem_req_wstrb,
    // XBAR -> core response
    input   logic        dmem_rsp_ready,
    output  logic [31:0] dmem_rsp_rdata,
    output  logic        dmem_rsp_valid,
    output  logic        dmem_rsp_err,

    // RAM
    // XBAR -> RAM request
    output  logic        ram_req_valid,
    input   logic        ram_req_ready,
    output  logic        ram_req_write,
    output  logic [31:0] ram_req_addr,
    output  logic [31:0] ram_req_wdata,
    output  logic [3:0]  ram_req_wstrb,
    // RAM -> XBAR response
    output  logic        ram_rsp_ready,
    input   logic [31:0] ram_rsp_rdata,
    input   logic        ram_rsp_valid,
    
    // MMIO
    // XBAR -> MMIO request
    output  logic        mmio_req_valid,
    input   logic        mmio_req_ready,
    output  logic        mmio_req_write,
    output  logic [31:0] mmio_req_addr,
    output  logic [31:0] mmio_req_wdata,
    output  logic [3:0]  mmio_req_wstrb,
    // MMIO -> XBAR response
    output  logic        mmio_rsp_ready,
    input   logic [31:0] mmio_rsp_rdata,
    input   logic        mmio_rsp_valid,

    //err
    output  logic        bus_err
);
    
    //unmapped
    logic unm_req_valid;
    logic unm_rsp_valid;

    typedef enum logic [1:0] {SEL_UNMAPPED, SEL_RAM, SEL_MMIO} sel_e;
    sel_e sel, sel_q;
    assign ram_req_addr   = dmem_req_addr;
    assign ram_req_write  = dmem_req_write;
    assign ram_req_wdata  = dmem_req_wdata;
    assign ram_req_wstrb  = dmem_req_wstrb;

    assign mmio_req_addr  = dmem_req_addr;
    assign mmio_req_write = dmem_req_write;
    assign mmio_req_wdata = dmem_req_wdata;
    assign mmio_req_wstrb = dmem_req_wstrb;

    assign ram_req_valid  = dmem_req_valid && (sel == SEL_RAM);
    assign mmio_req_valid = dmem_req_valid && (sel == SEL_MMIO);
    assign unm_req_valid =  dmem_req_valid && (sel == SEL_UNMAPPED);

    assign dmem_rsp_err = dmem_rsp_valid && (sel_q == SEL_UNMAPPED);

    always_ff @(posedge clk) begin
        unm_rsp_valid <= dmem_req_ready && unm_req_valid;
        if (rst) begin
            sel_q <= SEL_UNMAPPED;
            bus_err <= 1'b0;
            unm_rsp_valid <= 1'b0;
        end
        else begin 
            if (dmem_req_valid && dmem_req_ready) sel_q <= sel;
            if (unm_req_valid && dmem_req_ready) bus_err <= 1'b1;
        end
    end
    // A misaligned base would silently decode as the aligned one below it.
    if (RAM_BASE[RAM_AW-1:0] != '0) begin : g_bad_ram_base
        $error("dmem_xbar: RAM_BASE %h not aligned to 2**RAM_AW", RAM_BASE);
    end
    if (MMIO_BASE[MMIO_AW-1:0] != '0) begin : g_bad_mmio_base
        $error("dmem_xbar: MMIO_BASE %h not aligned to 2**MMIO_AW", MMIO_BASE);
    end

    always_comb begin
        if (dmem_req_addr[31:RAM_AW] == RAM_BASE[31:RAM_AW]) sel = SEL_RAM;
        else if (dmem_req_addr[31:MMIO_AW] == MMIO_BASE[31:MMIO_AW]) sel = SEL_MMIO;
        else sel = SEL_UNMAPPED;
    end
    always_comb begin
        dmem_rsp_valid = 1'b0;
        dmem_rsp_rdata = 32'b0;
        ram_rsp_ready = 1'b0;
        mmio_rsp_ready = 1'b0;
        case (sel_q)
            SEL_RAM: begin
                ram_rsp_ready  = dmem_rsp_ready;
                dmem_rsp_valid = ram_rsp_valid;
                dmem_rsp_rdata = ram_rsp_rdata;
            end
            SEL_MMIO: begin
                mmio_rsp_ready  = dmem_rsp_ready;
                dmem_rsp_valid = mmio_rsp_valid;
                dmem_rsp_rdata = mmio_rsp_rdata;
            end
            SEL_UNMAPPED: begin
                dmem_rsp_valid = unm_rsp_valid;
                
                dmem_rsp_rdata = 32'b0;
            end
            default: begin
                dmem_rsp_rdata = 32'b0;
            end
        endcase
    end

    always_comb begin
        dmem_req_ready = 1'b0;
        case (sel)
            SEL_RAM:      dmem_req_ready = ram_req_ready;
            SEL_MMIO:     dmem_req_ready = mmio_req_ready;
            SEL_UNMAPPED: dmem_req_ready = 1'b1;
            default:      dmem_req_ready = 1'b0;
        endcase
    end

endmodule