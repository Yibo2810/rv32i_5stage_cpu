`timescale 1ns/1ps
module core_assertions (
    core_mem_if.monitor mem
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

    sys_trap_flags_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !$isunknown({mem.cb.sys_ecall, mem.cb.sys_ebreak})
    ) else fail_count++;

    sys_trap_flags_exclusive: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !(mem.cb.sys_ecall && mem.cb.sys_ebreak)
    ) else fail_count++;

    sys_ecall_only_for_ecall_instr: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.sys_ecall |-> (mem.cb.imem_rdata === RV_ECALL_INSTR)
    ) else fail_count++;

    sys_ebreak_only_for_ebreak_instr: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.sys_ebreak |-> (mem.cb.imem_rdata === RV_EBREAK_INSTR)
    ) else fail_count++;
    // for others
    no_dmem_side_effect_during_reset: assert property (
        @(mem.cb)
        mem.cb.rst |-> (!mem.cb.dmem_read && !mem.cb.dmem_write)
    ) else fail_count++;

    imem_addr_aligned: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.imem_addr[1:0] == 2'b00
    ) else fail_count++;

    imem_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !$isunknown({mem.cb.imem_addr, mem.cb.imem_rdata})
    ) else fail_count++;

    dmem_read_write_exclusive: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !(mem.cb.dmem_read && mem.cb.dmem_write)
    ) else fail_count++;

    dmem_ctrl_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        !$isunknown({mem.cb.dmem_read, mem.cb.dmem_write, mem.cb.dmem_wstrb})
    ) else fail_count++;

    dmem_read_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_read |-> !$isunknown({mem.cb.dmem_addr, mem.cb.dmem_rdata})
    ) else fail_count++;

    dmem_write_known: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_write |-> !$isunknown({mem.cb.dmem_addr, mem.cb.dmem_wdata, mem.cb.dmem_wstrb})
    ) else fail_count++;

    dmem_read_only_for_load: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_read |-> (mem.cb.imem_rdata[6:0] == OPCODE_LOAD)
    ) else fail_count++;

    dmem_write_only_for_store: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_write |-> (mem.cb.imem_rdata[6:0] == OPCODE_STORE)
    ) else fail_count++;

    a_load_addr_aligned: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_read |-> load_addr_aligned(mem.cb.imem_rdata[14:12], mem.cb.dmem_addr[1:0])
    ) else fail_count++;

    store_wstrb_matches_width_and_addr: assert property (
        @(mem.cb)
        disable iff (mem.cb.rst)
        mem.cb.dmem_write |-> store_wstrb_ok(mem.cb.imem_rdata[14:12], mem.cb.dmem_addr[1:0], mem.cb.dmem_wstrb)
    ) else fail_count++;
endmodule