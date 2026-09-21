`timescale 1ns/1ps
module pipeline_assertions (
    pipeline_probe_if.pipeline_monitor mem
);
    int unsigned fail_count;

    function automatic bit load_addr_aligned(
        input logic [2:0] funct3,
        input logic [1:0] off
    );
        case (funct3)
            FUNCT3_LB, FUNCT3_LBU: return 1'b1;
            FUNCT3_LH, FUNCT3_LHU: return off[0] == 1'b0;
            FUNCT3_LW:             return off == 2'b00;
            default:               return 1'b0;
        endcase
    endfunction

    function automatic bit store_wstrb_ok(
        input logic [2:0] funct3,
        input logic [1:0] off,
        input logic [3:0] wstrb
    );
        case (funct3)
            FUNCT3_SB:
                return wstrb == (4'b0001 << off);

            FUNCT3_SH:
                return (off[0] == 1'b0) &&
                       (wstrb == (4'b0011 << off));

            FUNCT3_SW:
                return (off == 2'b00) &&
                       (wstrb == 4'b1111);

            default:
                return 1'b0;
        endcase
    endfunction
    //all for sys
    localparam logic [31:0] RV_ECALL_INSTR  = 32'h0000_0073;
    localparam logic [31:0] RV_EBREAK_INSTR = 32'h0010_0073;

    no_dmem_side_effect_during_reset: assert property (
        @(mem.cb)
        mem.cb.rst |-> (mem.cb.dmem_req_valid !== 1'b1 && mem.cb.dmem_req_write !== 1'b1)
    ) else begin fail_count++; $error("check no_dmem_side_effect_during_reset failed"); end

    imem_addr_aligned: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.imem_addr[1:0] == 2'b00
    ) else begin fail_count++; $error("check imem_addr_aligned failed"); end

    imem_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !$isunknown({mem.cb.imem_addr, mem.cb.imem_rdata})
    ) else begin fail_count++; $error("check imem_known failed"); end

    dmem_read_wstrb: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && !mem.cb.dmem_req_write |-> (mem.cb.dmem_req_wstrb == 4'b0000)
    ) else begin fail_count++; $error("check dmem_read_wstrb failed"); end

    dmem_ctrl_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !$isunknown({mem.cb.dmem_req_valid, mem.cb.dmem_req_write, mem.cb.dmem_req_wstrb})
    ) else begin fail_count++; $error("check dmem_ctrl_known failed"); end

    dmem_read_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && !mem.cb.dmem_req_write |-> !$isunknown({mem.cb.dmem_req_addr})
    ) else begin fail_count++; $error("check dmem_read_known failed"); end

    dmem_write_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && mem.cb.dmem_req_write |-> !$isunknown({mem.cb.dmem_req_addr, mem.cb.dmem_req_wdata, mem.cb.dmem_req_wstrb})
    ) else begin fail_count++; $error("check dmem_write_known failed"); end

    dmem_read_only_for_load: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && !mem.cb.dmem_req_write |-> (mem.cb.mem_instr[6:0] == OPCODE_LOAD)
    ) else begin fail_count++; $error("check dmem_read_only_for_load failed"); end

    dmem_write_only_for_store: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && mem.cb.dmem_req_write |-> (mem.cb.mem_instr[6:0] == OPCODE_STORE)
    ) else begin fail_count++; $error("check dmem_write_only_for_store failed"); end

    a_load_addr_aligned: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && !mem.cb.dmem_req_write |-> load_addr_aligned(mem.cb.mem_instr[14:12], mem.cb.dmem_req_addr[1:0])
    ) else begin fail_count++; $error("check a_load_addr_aligned failed"); end

    store_wstrb_matches_width_and_addr: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_req_valid && mem.cb.dmem_req_write |-> store_wstrb_ok(mem.cb.mem_instr[14:12], mem.cb.dmem_req_addr[1:0], mem.cb.dmem_req_wstrb)
    ) else begin fail_count++; $error("check store_wstrb_matches_width_and_addr failed"); end
endmodule